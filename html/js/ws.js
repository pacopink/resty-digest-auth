var ws = new WebSocket('ws://localhost:28081/ws');

ws.onmessage = function(event) {
  console.log('Count is: ' + event.data);
};

ws.onopen = function(evt) {
  console.log('Openned');
  ws.send("ping");
}
