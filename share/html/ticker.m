
function ticker() {
  if ( dataLast == null ) {
    document.getElementById("dataLast").style.color = "yellow";
    return;
  }
  const timeNow = Date.now();

  if ( timeNow - dataLast.getTime() > dataStale ) {
    document.getElementById("dataLast").style.color = "red";
  } else {
    document.getElementById("dataLast").style.color = "black";
  }

  const spinner = "_.:^*  ".split("");   // "-\\|/".split("");
  spinState++;
  document.getElementById("spinner").textContent = spinner[spinState % spinner.length];
}
