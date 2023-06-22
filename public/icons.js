window.onload = () => {
    icons = document.querySelectorAll("[data-icon='true']");

    for(let i=0; i <icons.length; i++){
        const icon = icons[i];
        icon.addEventListener('click', chooseIcon);
    }

    function chooseIcon(event) {
        const icon = event.target;
        const iconName = icon.dataset.name;
        console.log(iconName);

        iconInput = document.getElementById("icon_input");
        iconInput.value = iconName;
    }

    colors = document.querySelectorAll("[data-color='true']");

    for(let i=0; i <colors.length; i++){
        const color = colors[i];
        color.addEventListener('click', chooseColor);
    }

    function chooseColor(event) {
        const color = event.target;
        const colorName = color.dataset.name;
        console.log(colorName);

        colorInput = document.getElementById("new_color");
        colorInput.value = colorName;
    }
}