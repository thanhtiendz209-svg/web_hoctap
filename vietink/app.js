import { createEditor } from './editor.js?v=0.3.0';

const icons = {
  new: '<path d="M12 19H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h8l4 4v4m-5-8v5h5m0 5v7m-3.5-3.5h7"/>',
  fullscreen: '<path d="M9 4H4v5m11-5h5v5M4 15v5h5m11-5v5h-5"/>',
  exit: '<path d="M4 9h5V4m11 5h-5V4M4 15h5v5m11-5h-5v5"/>',
  download: '<path d="M12 3v12m-4-4 4 4 4-4M4 16v3a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-3"/>',
  undo: '<path d="M8 5 4 9l4 4m-4-4h10a5 5 0 0 1 0 10h-1"/>',
  redo: '<path d="m16 5 4 4-4 4m4-4H10a5 5 0 0 0 0 10h1"/>',
  pen: '<path d="m5 19 3-1 10-10-3-3L5 15l-1 5 1-1Zm9-13 3 3m-3-4 2-2 4 4-2 2M8 18l-3-3"/>',
  pencil: '<path d="m4 20 1-5L16 4l4 4L9 19l-5 1Zm10-14 4 4M5 15l4 4m-2-2L16 8"/>',
  marker: '<path d="m3 19 4-1 2-2-3-3-2 2-1 4Zm3-6 9-9 5 5-9 9-5-5Zm7-7 5 5M3 21h9"/>',
  eraser: '<path d="m11 20-7-7a2 2 0 0 1 0-2.8l6.7-6.7a2 2 0 0 1 2.8 0l7 7a2 2 0 0 1 0 2.8l-6.7 6.7H11ZM8 7.5l8.5 8.5M12 20h8"/>',
  select: '<rect x="4" y="4" width="16" height="16" rx="2" stroke-dasharray="2.6 3"/><path d="m9 9 2.2 6 1.3-2.5L15 11 9 9Z"/>',
  shapes: '<path d="m7.5 4 4.5 7H3l4.5-7Z"/><rect x="3.5" y="14.5" width="6" height="6" rx=".75"/><circle cx="17.5" cy="15.5" r="4"/>',
  laser: '<path d="m5 19 4-4m6-6 4-4m-2 4V5m-8 12 4-4m-3 5 2-2"/><circle cx="6" cy="7" r="1.5"/><path d="M4 21h8"/>',
  hand: '<path d="M8 12V6a1.5 1.5 0 0 1 3 0v5-7a1.5 1.5 0 1 1 3 0v7-5a1.5 1.5 0 1 1 3 0v6-3a1.5 1.5 0 1 1 3 0v7a5 5 0 0 1-5 5h-2a5 5 0 0 1-4-2L4 14a1.5 1.5 0 0 1 2-2l2 2v-2Z"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  paper: '<path d="M6 3h9l4 4v14H6zM9 10h7m-7 4h7m-7 4h7"/>',
  minus: '<path d="M5 12h14"/>', plus: '<path d="M5 12h14m-7-7v14"/>',
  chevron: '<path d="m6 9 6 6 6-6"/>', close: '<path d="m6 6 12 12M18 6 6 18"/>',
  line: '<path d="m5 19 14-14"/>', rect: '<rect x="4" y="6" width="16" height="12" rx="1.5"/>',
  ellipse: '<ellipse cx="12" cy="12" rx="8" ry="6"/>',
  trash: '<path d="M4 7h16m-10 4v6m4-6v6M7 7l1 13h8l1-13M9 7V4h6v3"/>',
};

function icon(name) {
  return `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${icons[name]}</svg>`;
}

const $ = (id) => document.getElementById(id);
const all = (selector) => [...document.querySelectorAll(selector)];
for (const host of all('[data-icon]')) host.insertAdjacentHTML('afterbegin', icon(host.dataset.icon));

const nibNames = { pen: 'Bút bi', pencil: 'Bút chì', marker: 'Dạ quang' };
const shapeNames = { line: 'Đường thẳng', rect: 'Hình chữ nhật', ellipse: 'Hình elip' };
const colors = [
  ['#20334b', 'Xanh đen'], ['#186b5f', 'Xanh ngọc'], ['#276cc2', 'Xanh lam'],
  ['#8255b0', 'Tím'], ['#da5760', 'Đỏ hồng'], ['#f0b941', 'Vàng'],
  ['#171a20', 'Đen'], ['#697884', 'Xám'],
  ['#a2aeb9', 'Bạc'], ['#ffffff', 'Trắng'], ['#24a1b9', 'Xanh lơ'],
  ['#78a64d', 'Xanh lá'], ['#e28046', 'Cam'], ['#c25592', 'Hồng'], ['#805f50', 'Nâu'],
];
const brushes = {
  pen: { color: colors[0][0], width: 3, dashed: false },
  pencil: { color: '#697884', width: 2, dashed: false },
  marker: { color: '#f0b941', width: 6, dashed: false },
};
let mode = 'pen';
let nib = 'pen';
let shape = 'line';
let openedPanel = null;
let state;
const canvas = $('paper-canvas');

function renderState(next) {
  state = next;
  if (document.activeElement !== $('title')) $('title').value = next.title;
  $('paper').value = next.paper;
  $('zoom-fit').textContent = `${Math.round(next.zoom * 100)}%`;
  $('undo').disabled = !next.canUndo;
  $('redo').disabled = !next.canRedo;
  $('selection-strip').hidden = next.selectedCount === 0;
  $('selection-count').textContent = `Đã chọn ${next.selectedCount} đối tượng`;
  if (next.selectedCount && mode !== 'select') activate('select');
  $('save-status').lastChild.textContent = next.saved
    ? 'Đã lưu trên thiết bị'
    : next.saveError ? 'Chưa lưu được' : 'Đang lưu…';
}

const editor = createEditor(canvas, {
  onChange: renderState,
});

function activate(next) {
  mode = next;
  canvas.dataset.tool = next;
  editor.setTool(next);
  editor.setBrush(brushes[nib]);
  for (const button of all('[data-mode]')) {
    const selected = button.id === 'pen'
      ? next in brushes
      : button.id === 'shape' ? next in shapeNames : button.dataset.mode === next;
    button.setAttribute('aria-pressed', selected);
  }
  updateBrush();
}

function updateBrush() {
  const brush = brushes[nib];
  const penButton = $('pen');
  penButton.querySelector('svg').outerHTML = icon(nib);
  penButton.title = `${nibNames[nib]} (B)`;
  penButton.setAttribute('aria-label', nibNames[nib]);
  $('shape').title = shapeNames[shape];
  $('shape').setAttribute('aria-label', shapeNames[shape]);
  $('stroke-width').value = brush.width;
  $('stroke-size').value = `${brush.width} px`;
  $('dashed').checked = brush.dashed;
  const width = nib === 'marker' ? brush.width * 3 : nib === 'pencil' ? brush.width * 0.85 : brush.width;
  const preview = $('preview-stroke');
  preview.setAttribute('stroke', brush.color);
  preview.setAttribute('stroke-width', width);
  preview.setAttribute('stroke-opacity', nib === 'marker' ? '.36' : '1');
  preview.setAttribute('stroke-dasharray', brush.dashed ? `${width * 2.5} ${width * 2}` : '');
  for (const button of all('[data-color]')) {
    button.setAttribute('aria-pressed', button.dataset.color === brush.color);
  }
  for (const button of all('[data-nib]')) button.setAttribute('aria-pressed', button.dataset.nib === nib);
  for (const button of all('[data-shape]')) button.setAttribute('aria-pressed', button.dataset.shape === shape);
}

function setColor(color) {
  brushes[nib].color = color;
  activate(mode in shapeNames ? mode : nib);
}

function addSwatches(container, palette) {
  for (const [color, label] of palette) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'swatch';
    button.style.setProperty('--ink', color);
    button.dataset.color = color;
    button.title = label;
    button.setAttribute('aria-label', label);
    button.onclick = () => setColor(color);
    container.append(button);
  }
}

addSwatches($('quick-colors'), colors.slice(0, 5));
addSwatches($('swatches'), colors);
const custom = document.createElement('label');
custom.className = 'swatch custom-swatch';
custom.style.setProperty('--ink', 'conic-gradient(#ef606e, #ffc652, #56c759, #3b81e0, #ae65d0, #ef606e)');
custom.title = 'Màu tùy chỉnh';
const colorInput = document.createElement('input');
colorInput.type = 'color';
colorInput.setAttribute('aria-label', 'Màu tùy chỉnh');
colorInput.oninput = () => setColor(colorInput.value);
custom.append(colorInput);
$('swatches').append(custom);

function closePanel(restoreFocus = false) {
  if (!openedPanel) return;
  const { button, panel } = openedPanel;
  panel.hidden = true;
  button.setAttribute('aria-expanded', 'false');
  if (restoreFocus) button.focus();
  openedPanel = null;
}

function positionPanel() {
  if (!openedPanel) return;
  const { button, panel } = openedPanel;
  const rect = button.getBoundingClientRect();
  panel.style.left = `${Math.max(8, Math.min(rect.left - 28, innerWidth - panel.offsetWidth - 8))}px`;
  panel.style.top = `${rect.bottom + 10}px`;
}

for (const [buttonId, panelId] of [['brush-options', 'brush-panel'], ['shape-options', 'shape-panel']]) {
  const button = $(buttonId);
  const panel = $(panelId);
  button.onclick = () => {
    const wasOpen = openedPanel?.button === button;
    closePanel();
    if (wasOpen) return;
    colorInput.value = brushes[nib].color;
    openedPanel = { button, panel };
    panel.hidden = false;
    button.setAttribute('aria-expanded', 'true');
    positionPanel();
  };
}
for (const button of all('[data-close-panel]')) button.onclick = () => closePanel(true);
document.addEventListener('pointerdown', (event) => {
  if (openedPanel && !openedPanel.panel.contains(event.target) && !openedPanel.button.contains(event.target)) closePanel();
});
window.addEventListener('resize', positionPanel);
document.querySelector('.ribbon').addEventListener('scroll', positionPanel);

for (const button of all('[data-mode]')) {
  button.onclick = () => activate(button.id === 'pen' ? nib : button.id === 'shape' ? shape : button.dataset.mode);
}
for (const button of all('[data-nib]')) {
  button.onclick = () => {
    nib = button.dataset.nib;
    activate(nib);
  };
}
for (const button of all('[data-shape]')) {
  button.onclick = () => {
    shape = button.dataset.shape;
    closePanel(true);
    activate(shape);
  };
}
$('stroke-width').oninput = (event) => {
  brushes[nib].width = Number(event.target.value);
  activate(mode in shapeNames ? mode : nib);
};
$('dashed').onchange = (event) => {
  brushes[nib].dashed = event.target.checked;
  activate(mode in shapeNames ? mode : nib);
};

$('undo').onclick = () => editor.undo();
$('redo').onclick = () => editor.redo();
$('paper').onchange = () => editor.setPaper($('paper').value);
$('title').oninput = () => editor.setTitle($('title').value);
$('title').onblur = () => { $('title').value = state.title; };
$('title').onkeydown = (event) => { if (event.key === 'Enter') event.target.blur(); };
$('new').onclick = () => {
  if (confirm('Tạo ghi chú mới và thay thế ghi chú đang mở?')) editor.newNote();
};
$('export').onclick = () => editor.exportPng();
$('delete-selection').onclick = () => editor.deleteSelection();
$('zoom-out').onclick = () => editor.zoomBy(1 / 1.2);
$('zoom-in').onclick = () => editor.zoomBy(1.2);
$('zoom-fit').onclick = () => editor.fit();
$('fullscreen').hidden = !document.fullscreenEnabled;
$('fullscreen').onclick = async () => {
  try {
    if (document.fullscreenElement) await document.exitFullscreen();
    else await document.documentElement.requestFullscreen();
  } catch {
    $('fullscreen').focus();
  }
};
document.addEventListener('fullscreenchange', () => {
  const full = Boolean(document.fullscreenElement);
  const button = $('fullscreen');
  button.innerHTML = icon(full ? 'exit' : 'fullscreen');
  button.title = full ? 'Thoát toàn màn hình' : 'Toàn màn hình';
  button.setAttribute('aria-label', button.title);
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    if (openedPanel) closePanel(true);
    else editor.clearSelection();
    return;
  }
  if (event.target.matches('input, textarea, select, [contenteditable]')) return;
  const key = event.key.toLowerCase();
  if (event.ctrlKey || event.metaKey) {
    if (key === 'z' || key === 'y') {
      event.preventDefault();
      if (event.shiftKey || key === 'y') editor.redo();
      else editor.undo();
    }
    return;
  }
  if (event.altKey) return;
  if (key === 'delete') editor.deleteSelection();
  if (key === 'b') activate(nib);
  if (key === 'e') activate('eraser');
  if (key === 'v') activate('select');
});

activate(nib);
renderState(editor.getState());
