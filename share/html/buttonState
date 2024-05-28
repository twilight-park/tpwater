
      function buttonState(name, request, actual, title) {
            var state = "OFF";
            var color = "blue";
            if ( typeof actual === "number" ) {
                if ( actual == 1 ) {
                    state = " ON";
                }
                if ( request !== actual ) {
                    color = "#ff9900";
                } else {
                    if ( actual === 1 ) {
                        color = "green";
                    }
                }
            } else {
                state = "???";
            }

            document.getElementById(name).textContent = `${title} : ${state}`;
            document.getElementById(name).style.color = color;
      }
