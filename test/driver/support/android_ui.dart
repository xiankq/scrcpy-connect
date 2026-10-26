import 'package:xml/xml.dart';

/// uiautomator 的完整 XML 层级；由 XML 库处理转义与嵌套。
List<AndroidUiNode> parseAndroidUi(String source) =>
    XmlDocument.parse(source)
        .findAllElements('node')
        .map(AndroidUiNode._)
        .toList();

class AndroidUiNode {
  AndroidUiNode._(this._element);
  final XmlElement _element;

  String operator [](String key) => _element.getAttribute(key) ?? '';

  Iterable<AndroidUiNode> get ancestors => _element.ancestors
      .whereType<XmlElement>()
      .where((element) => element.name.qualified == 'node')
      .map(AndroidUiNode._);
}
