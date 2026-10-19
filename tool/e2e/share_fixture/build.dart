import "../build_fixture.dart" show buildFixture;
import "../support.dart" show cli;

Future<void> main(List<String> arguments) =>
    cli(() => buildFixture("share", arguments));
