import 'package:test/test.dart';

import '../../check_test_budget.dart' show rustTestLines;

void main() {
  test('Rust测试专属维护量不会被字符串、注释或生产代码混淆', () {
    const source = r'''fn production() {}
#[cfg(any(test, unix))]
fn shared() {}
#[cfg(all(test, unix))]
pub(crate) mod checks {
  const TEXT: &str = r###"} /*"###;
  /* } /* nested { */ } */
  fn fixture<'a>() { let _ = '}'; }
}
#[cfg(test)]
fn helper() {}
fn other_production() {}
''';
    expect(rustTestLines(source), 8);
    expect(
      rustTestLines(
        source.replaceFirst('fn production() {}', '''
fn production() {
  let text = "#[cfg(test)] fake {";
}
'''),
      ),
      8,
    );
    expect(
      rustTestLines(
        source.replaceFirst('fn helper() {}', '''fn helper() {
  let fixture = 1;
}'''),
      ),
      10,
    );
  });
}
