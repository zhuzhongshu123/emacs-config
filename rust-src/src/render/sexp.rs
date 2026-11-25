//! Emacs wire format v1. All offsets count Unicode scalar values, start at
//! zero, and use exclusive ends. Output is data, never executable Lisp.
use crate::{layout, parser, theme, Args};
use anyhow::Result;
use comrak::{parse_document, Arena};
use std::fmt::Write;

fn string(out: &mut String, value: &str) {
    out.push('"');
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c.is_control() => {
                write!(out, "\\u{:04x}", c as u32).unwrap();
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

pub fn render_emacs(source: &str, args: &Args) -> Result<String> {
    let prepared = parser::frontmatter::prepare(source, args.frontmatter);
    // Frontmatter replacement/removal changes only the prefix. Wikilinks
    // preserve line counts; heading source lines can therefore be restored.
    let line_delta = source.lines().count() as isize - prepared.lines().count() as isize;
    let content = crate::wikilink::process_wikilinks(&prepared);
    let arena = Arena::new();
    let root = parse_document(&arena, &content, &parser::options_for(&content));
    let t = theme::resolve_theme(&args.theme);
    let width = args.width.columns().unwrap_or(80);
    let result = layout::layout_document(
        root,
        &t,
        width.saturating_sub(2).max(8),
        args.spacing,
        2,
        None,
        crate::image::ImageMode::Off,
        None,
    );
    Ok(serialize(&result, width, line_delta))
}

fn serialize(result: &layout::LayoutResult, width: u16, line_delta: isize) -> String {
    let mut text = String::new();
    let mut starts = Vec::new();
    let mut styles: Vec<(layout::SpanStyle, Option<u8>)> = Vec::new();
    let mut runs: Vec<(usize, usize, usize)> = Vec::new();
    let mut offset = 0;
    for (line_index, line) in result.lines.iter().enumerate() {
        starts.push(offset);
        let heading = result
            .headings
            .iter()
            .find(|h| h.line_index == line_index)
            .map(|h| h.level);
        for span in &line.spans {
            let length = span.text.chars().count();
            if length == 0 {
                continue;
            }
            let key = (span.style.clone(), heading);
            let index = styles.iter().position(|s| *s == key).unwrap_or_else(|| {
                styles.push(key);
                styles.len() - 1
            });
            if let Some(last) = runs.last_mut().filter(|r| r.1 == offset && r.2 == index) {
                last.1 += length;
            } else {
                runs.push((offset, offset + length, index));
            }
            text.push_str(&span.text);
            offset += length;
        }
        text.push('\n');
        offset += 1;
    }
    starts.push(offset);
    let mut out = format!("(:version 1 :offset-unit unicode-scalar :width {width} :text ");
    string(&mut out, &text);
    out.push_str(" :styles [");
    for (style, heading) in &styles {
        out.push('(');
        if let Some(level) = heading {
            write!(out, ":role heading :level {level} ").unwrap();
        }
        for (key, value) in [
            (":fg", &style.fg),
            (":bg", &style.bg),
            (":link", &style.link_url),
            (":footnote", &style.footnote),
        ] {
            if let Some(value) = value {
                out.push_str(key);
                out.push(' ');
                string(&mut out, value);
                out.push(' ');
            }
        }
        for (key, enabled) in [
            (":bold", style.bold),
            (":italic", style.italic),
            (":underline", style.underline),
            (":strike", style.strikethrough),
            (":dim", style.dim),
        ] {
            if enabled {
                write!(out, "{key} t ").unwrap();
            }
        }
        out.push(')');
    }
    out.push_str("] :runs [");
    for (start, end, style) in runs {
        write!(out, "({start} {end} {style})").unwrap();
    }
    out.push_str("] :headings [");
    for heading in &result.headings {
        let source_line = (heading.source_line as isize + line_delta).max(1);
        write!(out, "({} {} ", starts[heading.line_index], heading.level).unwrap();
        string(&mut out, &heading.text);
        out.push(' ');
        string(&mut out, &heading.anchor);
        write!(out, " {source_line})").unwrap();
    }
    out.push_str("] :code-blocks [");
    for block in &result.code_blocks {
        write!(
            out,
            "({} {} ",
            starts[block.line_index],
            starts[block.line_index + block.rows]
        )
        .unwrap();
        string(&mut out, &block.lang);
        out.push(' ');
        string(&mut out, &block.source);
        out.push_str(" [");
        for fragment in &block.fragments {
            let start = starts[fragment.line_index] + fragment.column;
            write!(
                out,
                "({start} {} {})",
                start + fragment.chars,
                fragment.source_offset
            )
            .unwrap();
        }
        out.push_str("])");
    }
    out.push_str("] :footnotes [");
    for note in &result.footnotes {
        out.push('(');
        string(&mut out, &note.name);
        out.push(' ');
        let text = note
            .lines
            .iter()
            .map(|l| l.spans.iter().map(|s| s.text.as_str()).collect::<String>())
            .collect::<Vec<_>>()
            .join("\n");
        string(&mut out, &text);
        out.push(')');
    }
    out.push_str("])\n");
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lisp_strings_escape_delimiters_and_controls() {
        let mut out = String::new();
        string(&mut out, "中文👩‍💻\"\\\n\t\r\u{1}");
        assert_eq!(out, "\"中文👩‍💻\\\"\\\\\\n\\t\\r\\u0001\"");
    }

    #[test]
    fn offsets_count_characters_and_coalesce_styles() {
        let style = layout::SpanStyle::default();
        let result = layout::LayoutResult {
            lines: vec![layout::StyledLine {
                spans: vec![
                    layout::StyledSpan {
                        text: "中".into(),
                        style: style.clone(),
                    },
                    layout::StyledSpan {
                        text: "文🙂".into(),
                        style,
                    },
                ],
            }],
            headings: vec![],
            images: vec![],
            code_blocks: vec![],
            footnotes: vec![],
        };
        let out = serialize(&result, 80, 0);
        assert!(out.contains(":runs [(0 3 0)]"));
        assert!(out.contains(":text \"中文🙂\\n\""));
    }

    #[test]
    fn frontmatter_heading_lines_are_original_lines() {
        let out = render_emacs("---\ntitle: Test\n---\n# 中文\n", &Args::default()).unwrap();
        assert!(out.contains("\"中文\" 4)"));
    }
}
