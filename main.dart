import "dart:async";
import "dart:collection";
import "dart:io";

import "package:polymorphic_bot/api.dart";

@PluginInstance()
Plugin plugin;
@BotInstance()
BotConnector bot;
@PluginStorage("logging")
Storage storage;

main(args, port) => polymorphic(args, port);

Timer _timer;

@Start()
void start() {
  plugin.log("Loading");
}

@Command("nolog", permission: "nolog")
nolog(CommandEvent event) {
  if (event.args.length != 1) {
    event.reply("> Usage: nolog <channel>");
    return;
  }
  
  var channel = "${event.network}:${event.channel.substring(1)}";
  
  if (storage.isInList("nolog", channel)) {
    event.reply("> ERROR: Logging is not enabled for this channel.");
    return;
  }
  
  storage.addToList("nolog", channel);
  event.reply("> Logging in ${event.channel} has been disabled.");
}

@Command("logme", permission: "logme")
logme(CommandEvent event) {
  if (event.args.length != 1) {
    event.reply("> Usage: logme <channel>");
    return;
  }
  
  var channel = "${event.network}:${event.channel}";
  
  if (!storage.isInList("nolog", channel)) {
    event.reply("> ERROR: Logging is already enabled for this channel.");
    return;
  }
  
  storage.removeFromList("nolog", channel);
  event.reply("> Logging in ${event.channel} has been enabled.");
}

@Start()
void startTimer() {
  _timer = new Timer.periodic(new Duration(seconds: 5), (_) {
    flushLogs();
  });
}

void flushLogs() {
  var map = <String, List<LogEntry>>{};
  
  while (_queue.isNotEmpty) {
    var entry = _queue.removeFirst();
    var simpleName = "${entry.network}/${entry.channel.substring(1)}";
    
    if (map.containsKey(simpleName)) {
      map[simpleName].add(entry);
    } else {
      map[simpleName] = <LogEntry>[entry];
    }
  }
  
  for (var name in map.keys) {
    var file = new File("logs/${name}.txt");
    
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    
    var content = map[name].map((entry) {
      return entry.format();
    }).join("\n") + "\n";
    
    file.writeAsStringSync(content, mode: FileMode.APPEND);
  }
}

const List<String> TRUE_VALUES = const["", "true", "1", "yes"];
const List<String> FALSE_VALUES = const ["false", "0", "no"];

@HttpEndpoint("/")
httpRoot(HttpRequest request) => HttpHelper.notFound(request);

@DefaultEndpoint()
httpDefault(HttpRequest request, HttpResponse response) {
  var qp = request.uri.queryParameters;
  var segments = request.uri.pathSegments;
  if (segments.length == 2 && fileExists("logs/${segments[0]}/${segments[1]}")) {
    var file = new File("logs/${segments[0]}/${segments[1]}");
    file.readAsLines().then((lines) {
      if (TRUE_VALUES.contains(qp["full"]) || request.uri.query != null && request.uri.query.endsWith("full")) {
        response.writeln(lines.join("\n"));
      } else {
        var end = lines.length - 1;
        var start = end - 100;
        if (start < 0) start = 0;
        response.writeln(lines.getRange(start, end).join("\n"));
      }
      response.close();
    });
  } else {
    HttpHelper.notFound(request);
  }
}

bool fileExists(String path) => new File(path).existsSync();

void addEntry(LogEntry entry) {
  if (storage.isInList("nolog", "${entry.network}:${entry.channel}")) {
    return;
  }
  
  _queue.add(entry);
}

@Shutdown()
void stopTimer() {
  if (_timer.isActive) {
    _timer.cancel();
  }
}

@OnJoin()
void handleJoin(JoinEvent event) {
  addEntry(new LogEntry(event.network, event.channel, "${event.user} joined"));
}

@OnPart()
void handlePart(PartEvent event) {
  addEntry(new LogEntry(event.network, event.channel, "${event.user} left"));
}

@OnAction()
void handleAction(ActionEvent event) {
  addEntry(new LogEntry(event.network, event.target, "* ${event.user} ${DisplayHelpers.clean(event.message)}"));
}

@OnMessage()
void handleMessage(MessageEvent event) {
  if (event.isPrivate) return;
  
  addEntry(new LogEntry(event.network, event.target, "<${event.from}> ${DisplayHelpers.clean(event.message)}"));
}

@OnQuitPart()
void handleQuitPart(QuitPartEvent event) {
  addEntry(new LogEntry(event.network, event.channel, "${event.user} quit"));
}

Queue<LogEntry> _queue = new Queue<LogEntry>();

class LogEntry {
  final String network;
  final String channel;
  final String message;
  final DateTime timestamp;
  
  LogEntry(this.network, this.channel, this.message) : timestamp = new DateTime.now();
  LogEntry.notNow(this.network, this.channel, this.message, this.timestamp);
  
  String format() {
    var m = timestamp.toString();
    m = m.substring(0, m.indexOf("."));
    return "[${m}] ${message}";
  }
}
