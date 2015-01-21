import "dart:async";
import "dart:collection";
import "dart:io";

import "package:polymorphic_bot/api.dart";

@PluginInstance()
Plugin plugin;
@BotInstance()
BotConnector bot;
Storage storage;

main(args, port) => polymorphic(args, port);

Timer _timer;

@Start()
void start() {
  bot = plugin.getBot();
  plugin.log("Loading");
  storage = plugin.getStorage("logging");
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
    var simpleName = "${entry.network}/${entry.channel}";
    
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

@Start()
void httpServer() {
  plugin.createHttpRouter().then((router) {
    router.addRoute("/", (request) {
      request.response
        ..statusCode = 404
        ..writeln("Not Found.")
        ..close();
    });
    
    router.defaultRoute((request) {
      var segments = request.uri.pathSegments;
      if (segments.length == 2 && fileExists("logs/${segments[0]}/${segments[1]}")) {
        var file = new File("logs/${segments[0]}/${segments[1]}");
        var stream = file.openRead();
        
        request.response.addStream(stream).then((_) {
          return request.response.close();
        });
      } else {
        request.response
          ..statusCode = 404
          ..writeln("Not Found.")
          ..close();
      }
    });
  });
}

bool fileExists(String path) => new File(path).existsSync();

void addEntry(LogEntry entry) {
  if (storage.isInList("nolog", "${entry.network}:${entry.channel}")) {
    return;
  }
  
  _queue.add(entry);
}

@EventHandler("shutdown")
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

@Start()
void handleOthers() {
  bot = plugin.getBot();
  
  bot.onCTCP((event) {
    if (!event.target.startsWith("#")) return;
    if (!event.message.startsWith("ACTION ")) return;
    
    var msg = event.message.substring("ACTION ".length);
    addEntry(new LogEntry(event.network, event.target, "* ${event.user} ${DisplayHelpers.clean(msg)}"));
  });
}

@OnMessage()
void handleMessage(MessageEvent event) {
  if (event.isPrivate) return;
  
  addEntry(new LogEntry(event.network, event.target, "<${event.from}> ${DisplayHelpers.clean(event.message)}"));
}

Queue<LogEntry> _queue = new Queue<LogEntry>();

class LogEntry {
  final String network;
  final String channel;
  final String message;
  final DateTime timestamp;
  
  LogEntry(this.network, this.channel, this.message) : timestamp = new DateTime.now();
  LogEntry.notNow(this.network, this.channel, this.message, this.timestamp);
  
  String format() => "[${timestamp}] ${message}";  
}
