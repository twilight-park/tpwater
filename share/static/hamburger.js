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
                    const viewportWidth = window.innerWidth;
                    
                    // Calculate the ideal left position (centered under the icon)
                    let leftPosition = iconCenterX - menuWidth / 2;
                    
                    // Adjust if the menu would overflow the right edge
                    if (leftPosition + menuWidth > viewportWidth) {
                        leftPosition = viewportWidth - menuWidth - 10; // 10px padding from right edge
                    }
                    
                    // Ensure the menu doesn't overflow the left edge
                    leftPosition = Math.max(10, leftPosition); // 10px padding from left edge
                    
                    menu.style.left = `${leftPosition}px`;
                    menu.style.top = `${iconBottom + window.scrollY + 10}px`;
                } else {
                    if (menu) {
                        menu.style.display = 'none';
                    }
                }
            }

    icon.addEventListener('click', toggleMenu);
}
