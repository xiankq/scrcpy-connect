/// 明确的工具动作仅保存在内存中，不能从 URL 自动重放。
enum RemoteTool { rotate, screen, key, text, launchApp }

class RemoteControlIntent {
  const RemoteControlIntent.rotate() : tool = RemoteTool.rotate, value = null;
  const RemoteControlIntent.screen(String mode)
    : tool = RemoteTool.screen,
      value = mode;
  const RemoteControlIntent.key(int code) : tool = RemoteTool.key, value = code;
  const RemoteControlIntent.text(String text)
    : tool = RemoteTool.text,
      value = text;
  const RemoteControlIntent.launchApp(String packageName)
    : tool = RemoteTool.launchApp,
      value = packageName;
  final RemoteTool tool;
  final Object? value;
}
