/// A deliberate tool action, held only in memory and never replayed from a URL.
enum RemoteTool { rotate, screen, key, text }

class RemoteControlIntent {
  const RemoteControlIntent.rotate() : tool = RemoteTool.rotate, value = null;
  const RemoteControlIntent.screen(String mode)
    : tool = RemoteTool.screen,
      value = mode;
  const RemoteControlIntent.key(int code) : tool = RemoteTool.key, value = code;
  const RemoteControlIntent.text(String text)
    : tool = RemoteTool.text,
      value = text;
  final RemoteTool tool;
  final Object? value;
}
