window.onload = () => {
    colors = document.querySelectorAll("li.list-group-item");

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