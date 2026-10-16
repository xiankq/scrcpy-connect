//! Bounded reader for the previous Android java.util.Properties journal.
//! Migration changes metadata only; source file paths and bytes never move.
use crate::{CoreError, CoreResult};
use std::{collections::BTreeMap, fs, path::Path};

pub(super) fn properties(path: &Path, limit: u64) -> CoreResult<BTreeMap<String, String>> {
    if fs::metadata(path)?.len() > limit {
        return Err(CoreError::new(
            "share_journal_limit",
            "分享来源记录过大，已保留待核对。",
        ));
    }
    let bytes = fs::read(path)?;
    let text: String = bytes.into_iter().map(char::from).collect();
    let mut result = BTreeMap::new();
    let mut logical = String::new();
    for physical in text.lines() {
        let line = physical.trim_start_matches([' ', '\t', '\u{c}']);
        if logical.is_empty() && (line.starts_with('#') || line.starts_with('!')) {
            continue;
        }
        logical.push_str(line);
        let trailing = logical.chars().rev().take_while(|c| *c == '\\').count();
        if trailing % 2 == 1 {
            logical.pop();
            continue;
        }
        if !logical.is_empty() {
            let mut escaped = false;
            let split = logical
                .char_indices()
                .find_map(|(index, c)| {
                    if escaped {
                        escaped = false;
                        None
                    } else if c == '\\' {
                        escaped = true;
                        None
                    } else if c == '=' || c == ':' || c.is_ascii_whitespace() {
                        Some(index)
                    } else {
                        None
                    }
                })
                .unwrap_or(logical.len());
            let key = unescape(&logical[..split])?;
            let rest = logical[split..].trim_start_matches([' ', '\t', '\u{c}']);
            let rest = rest
                .strip_prefix(['=', ':'])
                .unwrap_or(rest)
                .trim_start_matches([' ', '\t', '\u{c}']);
            result.insert(key, unescape(rest)?);
        }
        logical.clear();
    }
    if !logical.is_empty() {
        return Err(CoreError::new(
            "share_journal_invalid",
            "分享来源记录未写完，已保留待核对。",
        ));
    }
    Ok(result)
}

fn unescape(input: &str) -> CoreResult<String> {
    let mut units = Vec::new();
    let mut chars = input.chars();
    while let Some(c) = chars.next() {
        let value = if c != '\\' {
            c as u16
        } else {
            match chars.next() {
                Some('u') => {
                    let hex: String = chars.by_ref().take(4).collect();
                    if hex.len() != 4 {
                        return Err(CoreError::new(
                            "share_journal_invalid",
                            "分享来源字符记录不完整。",
                        ));
                    }
                    u16::from_str_radix(&hex, 16).map_err(|_| {
                        CoreError::new("share_journal_invalid", "分享来源字符记录无效。")
                    })?
                }
                Some('n') => b'\n' as u16,
                Some('r') => b'\r' as u16,
                Some('t') => b'\t' as u16,
                Some('f') => 12,
                Some(other) => other as u16,
                None => {
                    return Err(CoreError::new(
                        "share_journal_invalid",
                        "分享来源记录未写完。",
                    ));
                }
            }
        };
        units.push(value);
    }
    String::from_utf16(&units)
        .map_err(|_| CoreError::new("share_journal_invalid", "分享来源 Unicode 记录无效。"))
}
