import "dart:async";
import "dart:collection";
import "dart:io";

import "package:polymorphic_bot/api.dart";

@PluginInstance()
Plugin plugin;

main(args, port) => polymorphic(args, port);

Timer _timer;

@Start()
void start() {
  plugin.log("Loading");
}

@Start()
void startTimer() {
  _timer = new Timer.periodic(new Duration(seconds: 5), (_) {
    var map = <String, List<MessageEvent>>{};
    
    while (_msgQueue.isNotEmpty) {
      var event = _msgQueue.removeFirst();
      var target = event.isPrivate ? "@${event.target}" : event.target.substring(1);
      var simpleName = "${event.network}/${target}";
      
      if (map.containsKey(simpleName)) {
        map[simpleName].add(event);
      } else {
        map[simpleName] = <MessageEvent>[event];
      }
    }
    
    for (var name in map.keys) {
      var file = new File("logs/${name}.txt");
      
      if (!file.existsSync()) {
        file.createSync(recursive: true);
      }
      
      var content = map[name].map((event) {
        return "<${event.from}> ${DisplayHelpers.clean(event.message)}";
      }).join("\n") + "\n";
      
      file.writeAsStringSync(content, mode: FileMode.APPEND);
    }
  });
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

@EventHandler("shutdown")
void stopTimer() {
  if (_timer.isActive) {
    _timer.cancel();
  }
}

@OnMessage()
void handleMessage(MessageEvent event) {
  _msgQueue.add(event);
}

Queue<MessageEvent> _msgQueue = new Queue<MessageEvent>();
