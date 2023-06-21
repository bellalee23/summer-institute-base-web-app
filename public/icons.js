window.onload = () => {
    icons = document.querySelectorAll("li.list-group-item");

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
}