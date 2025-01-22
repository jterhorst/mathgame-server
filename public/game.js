//
//  game.js
//  mathgame-server
//
//  Created by Jason Terhorst on 1/21/25.
//

var wsUri = "/game";
var connected = false;
var input;
var nameEntry;
var roomEntry;
var output;
//var question;
var question_lhs;
var question_rhs;
var intervalId;

function init()
{
    console.log("Setting up fields.")
    
    input = document.getElementById("input");
    nameEntry = document.getElementById("name_entry");
    roomEntry = document.getElementById("room_entry");
    output = document.getElementById("output_box");
//    question = document.getElementById("math_problem");
    question_lhs = document.getElementById("math_problem_lhs");
    question_rhs = document.getElementById("math_problem_rhs");

    input.value = ""
//    nameEntry.value = ""
//    roomEntry.value = ""
    
    console.log("Ready.")
    
    inputEnter();
}

function openWebSocket(uri)
{
  websocket = new WebSocket(uri);
  websocket.onopen = function(evt) { onOpen(evt) };
  websocket.onclose = function(evt) { onClose(evt) };
  websocket.onmessage = function(evt) { onMessage(evt) };
  websocket.onerror = function(evt) { onError(evt) };
  
  // intervalId = setInterval(function() {
  //   websocket.send(JSON.stringify({"type": "heartbeat", "data": "ping!"}));
  // }, 10000);
}

function onOpen(evt)
{
  document.getElementById("output_box").innerHTML = ""
  writeToScreen("CONNECTED");
}

function onClose(evt)
{
  document.getElementById("output_box").innerHTML = ""
  writeToScreen("DISCONNECTED");
  connected = false
  
  clearInterval(intervalId);
}

function onMessage(evt)
{
  writeToScreen('<span style="color: blue;">' + evt.data + '</span>');
  // console.log(JSON.parse(evt.data))
  var rawData = JSON.parse(evt.data)
    
    if (rawData.players != undefined) {
        var playersList = "<ul>"
        rawData.players.forEach((element, index) => {
            var style = " style=\"font-weight: bold\""
            playersList += "<li" + style + ">" + element.name + " - " + element.score + "</li>"
        })
        playersList += "</ul>"
        document.getElementById("players_list").innerHTML = playersList;
    }
    
    if (rawData.activeBattle && rawData.activeBattle.questions[nameEntry.value] != undefined) {
        let found = rawData.activeBattle.questions[nameEntry.value];
//        console.log("match: " + JSON.stringify(found))

      question_lhs.innerHTML = found.lhs; // + "<br /> x " + rawData.question.rhs + " <br /> ------<br />?";
      question_rhs.innerHTML = "x " + found.rhs;
  }
}

function onError(evt)
{
  writeToScreen('<span style="color: red;">ERROR:</span> ' + JSON.stringify(evt));
    console.log(JSON.stringify(evt));
}

function doSend(message)
{
  websocket.send(JSON.stringify({"type": "answer", "data": message}));
}

function writeToScreen(message)
{
  var pre = document.createElement("p");
  pre.style.wordWrap = "break-word";
  pre.innerHTML = message;
  output.appendChild(pre);
}

function inputEnter() {
    if (connected == false) {
        if (nameEntry.value == "") {
            return
        }
        if (roomEntry.value == "") {
            return
        }
        // hide enter name
//        let enterName = document.getElementById("enter_name")
//        enterName.style.display = 'none'
//        nameEntry.style.display = 'none'
//        roomEntry.style.display = 'none'
//        input.style.display = 'block'
//        question.style.display = 'block'
        // websocket connect
        let uri = wsUri + "?code=" + roomEntry.value + "&name=" + nameEntry.value
        openWebSocket(uri)
        connected = true
    } else {
        if (input.value == "") {
            return
        }
        doSend(input.value)
    }
    input.value = ""
}

//window.addEventListener("load", init, false);

console.log("Script loaded.")

//window.onload = init();

document.addEventListener('DOMContentLoaded', function() {
    init();
}, false);
