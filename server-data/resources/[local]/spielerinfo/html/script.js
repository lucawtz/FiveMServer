// spielerinfo: nimmt die Daten aus client.lua entgegen und baut das Panel neu auf.
// Texte werden nur per textContent gesetzt, nie als HTML.

const panel = document.getElementById('panel');
const toggleKey = document.getElementById('toggle-key');
const title = document.getElementById('title');
const hint = document.getElementById('hint');
const rows = document.getElementById('rows');
const footer = document.getElementById('footer');

function renderRows(data) {
    rows.replaceChildren();

    for (const entry of data.rows || []) {
        const row = document.createElement('div');
        row.className = 'row';

        const label = document.createElement('span');
        label.className = 'label';
        label.textContent = entry.label;
        row.appendChild(label);

        const value = document.createElement('span');
        value.className = entry.money ? 'value money' : 'value';
        value.textContent = entry.value;
        row.appendChild(value);

        rows.appendChild(row);
    }
}

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || data.action !== 'update') return;

    panel.classList.toggle('hidden', !data.visible);
    panel.classList.toggle('expanded', Boolean(data.expanded));
    panel.classList.toggle('left', data.side === 'left');
    panel.style.top = data.top || '';

    toggleKey.textContent = data.toggleKey;
    title.textContent = data.title;
    hint.textContent = data.hint;
    footer.textContent = data.footer;

    renderRows(data);
});
