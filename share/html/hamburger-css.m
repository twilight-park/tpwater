<style>
    .hamburger-icon {
        width: 35px;
        height: 35px;
        display: inline-block;
        padding: 5px;
        box-sizing: border-box;
        background-color: #f0f0f0;
        border-radius: 5px;
        flex-direction: column;
        justify-content: space-between;
        cursor: pointer;
    }
    .hamburger-icon hr {
        width: 80%;
        height: 4px;
        background-color: #333;
        border: none;
        margin: 4px;
        border-radius: 2px;
    }
        .menu-pane {
            display: none;
            position: absolute;
            background-color: white;
            border: 1px solid #ccc;
            border-radius: 5px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            min-width: 150px;
        }
        .menu-pane a {
            display: block;
            padding: 10px 20px;
            text-decoration: none;
            color: #333;
        }
        .menu-pane a:hover {
            background-color: #f0f0f0;
        }
</style>
