String shellQuote(String value) {
  if (value.contains('\u0000')) throw ArgumentError('shell 参数不能包含 NUL。');
  return "'${value.replaceAll("'", "'\\''")}'";
}
