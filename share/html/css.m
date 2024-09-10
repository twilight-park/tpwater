  <style type="text/css">
    html, body {
      height: 100%;
      margin: 0;
      padding: 0;
    }
    #flowChart {
       min-height: 50vh;
       width: 100vw;
    }
    .ct-series-a .ct-line {
        stroke: blue;
        stroke-width: 2;
    }

    .tophdr {
      display: inline;
      position: fixed;
      width: 95%
    }
    .tophdr h4 {
      display: inline;
    }
    .rite {
      display: inline;
      float: right
    }

    .box {
      display: flex;
      flex-direction: column;
      position: fixed;
      padding-top: 5vh;
      z-index: 1;
    }
    .box h1 {
      font-weight: bold;
      font-size: 38px;
      margin: 0;
      margin-left: 60px;
      background-color: rgba(255, 255, 255, .75);
      padding: 0;
    }

    .buthdr h1 {
      width: 100%;
      margin: 0;
    }

    div.buttons {
      position: relative;
      display: flex;
      min-height: 25vh;
      width: 100%;
      white-space: nowrap;
      align-items: center;
    }

    .buthdr {
      width: 100%;
      padding: 4px;
      display: inline;
    }
    .buthdr button {
      display: inline;
      font-weight: bold;
      font-size: 125%;
    }

    .pbutton {
      width: 100%;
    }
    .button {
      height: 100%;
      padding: 1px;
      margin: 1px;
    }

    @media (max-width: 768px) {
        .box {
            padding-top: 5vh;
        }
        .box h1 {
            font-size: 28px;
        }
        .buttons {
            flex-direction: column;
        }
    }
  </style>
