function hamburger(iconId, menuItems) {
    const icon = document.getElementById(iconId);
    let menu = null;

    function createMenu() {
        menu = document.createElement('div');
        menu.className = 'menu-pane';
        for (let [label, url] of Object.entries(menuItems)) {
            const link = document.createElement('a');
            link.href = url;
            link.textContent = label;
            link.onclick = (e) => {
                e.preventDefault();
                window.location.href = url;
                toggleMenu();
            };
            menu.appendChild(link);
        }
        document.body.appendChild(menu);
    }


    function toggleMenu() {
        icon.classList.toggle('active');
        if (icon.classList.contains('active')) {
            if (!menu) {
                createMenu();
            }
            const iconRect = icon.getBoundingClientRect();
            const iconCenterX = iconRect.left + iconRect.width / 2;
            const iconBottom = iconRect.bottom;

            menu.style.display = 'block';
            const menuWidth = menu.offsetWidth;

            menu.style.left = `${iconCenterX - menuWidth / 2}px`;
            menu.style.top = `${iconBottom + window.scrollY + 10}px`;
        } else {
            menu.style.display = 'none';
        }
    }

    icon.addEventListener('click', toggleMenu);
}
