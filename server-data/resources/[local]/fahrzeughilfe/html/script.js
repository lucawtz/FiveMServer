// fahrzeughilfe: nimmt die Daten aus client.lua entgegen und baut das Panel neu auf.
// Texte werden nur per textContent gesetzt, nie als HTML.

const panel = document.getElementById('panel');
const toggleKey = document.getElementById('toggle-key');
const title = document.getElementById('title');
const hint = document.getElementById('hint');
const groups = document.getElementById('groups');
const footer = document.getElementById('footer');

function createKey(text, unbound) {
    const key = document.createElement('span');
    key.className = unbound ? 'key unbound' : 'key';
    key.textContent = text;
    return key;
}

function renderGroups(data) {
    groups.replaceChildren();

    for (const group of data.groups || []) {
        const section = document.createElement('div');
        section.className = 'group';

        const heading = document.createElement('div');
        heading.className = 'group-title';
        heading.textContent = group.title;
        section.appendChild(heading);

        for (const entry of group.entries) {
            const row = document.createElement('div');
            row.className = 'row';
            row.appendChild(createKey(entry.key, entry.key === data.unboundText));

            const label = document.createElement('span');
            label.className = 'label';
            label.textContent = entry.label;
            row.appendChild(label);

            section.appendChild(row);
        }

        groups.appendChild(section);
    }
}

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || data.action !== 'update') return;

    panel.classList.toggle('hidden', !data.visible);
    panel.classList.toggle('expanded', Boolean(data.expanded));
    panel.classList.toggle('right', data.side === 'right');

    toggleKey.textContent = data.toggleKey;
    title.textContent = data.title;
    hint.textContent = data.hint;
    footer.textContent = data.footer;

    renderGroups(data);
});
