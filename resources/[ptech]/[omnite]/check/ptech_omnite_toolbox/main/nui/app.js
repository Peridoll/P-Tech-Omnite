const panel = document.getElementById('copy-panel');
const textArea = document.getElementById('config-line');
const status = document.getElementById('status');

function nuiPost(name, data = {}) {
    return fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    });
}

window.addEventListener('message', (event) => {
    if (event.data?.action !== 'copyText') return;
    textArea.value = event.data.text || '';
    status.textContent = '';
    panel.classList.remove('hidden');
    document.getElementById('copy-button').focus();
});

document.getElementById('copy-button').addEventListener('click', async () => {
    let success = false;
    try {
        if (navigator.clipboard?.writeText) {
            await navigator.clipboard.writeText(textArea.value);
            success = true;
        }
    } catch (_) {}

    if (!success) {
        textArea.focus();
        textArea.select();
        success = document.execCommand('copy');
    }

    status.textContent = success ? 'コピーしました。設定ファイルへ貼り付けてください。' : 'コピーに失敗しました。設定行を選択して手動でコピーしてください。';
    await nuiPost('clipboardResult', { success });
    if (success) panel.classList.add('hidden');
});

document.getElementById('close-button').addEventListener('click', async () => {
    panel.classList.add('hidden');
    await nuiPost('clipboardCancel');
});

document.addEventListener('keydown', async (event) => {
    if (event.key !== 'Escape' || panel.classList.contains('hidden')) return;
    panel.classList.add('hidden');
    await nuiPost('clipboardCancel');
});

const placementPanel = document.getElementById('placement-panel');
const sliders = [...placementPanel.querySelectorAll('input[type="range"]')];
const numberInputs = new Map();
const numericLabels = {right:'左右（m）',forward:'前後（m）',height:'高さ（m）',heading:'向き（度）',style:'座り方の番号'};
for (const slider of sliders) {
    const input = document.createElement('input');
    input.type = 'number';
    input.id = `number-${slider.dataset.key}`;
    input.className = 'numeric-input';
    input.setAttribute('aria-label', numericLabels[slider.dataset.key]);
    slider.before(input);
    numberInputs.set(slider.dataset.key, input);
}
const saveButton = document.getElementById('placement-save');
const cancelButton = document.getElementById('placement-cancel');
const focusButton = document.getElementById('placement-focus');
const groundButton = document.getElementById('placement-ground');
const placementError = document.getElementById('placement-error');
let placement = null;
let updateTimer;
let pendingValues;
let updateChain = Promise.resolve();

function values() {
    return Object.fromEntries(sliders.map(input => [input.dataset.key, Number(input.value)]));
}

function renderValues() {
    const v = values();
    for (const key of ['right', 'forward', 'height']) {
        document.getElementById(`value-${key}`).textContent = `${v[key] > 0 ? '+' : ''}${v[key].toFixed(2)} m`;
    }
    document.getElementById('value-heading').textContent = `${v.heading.toFixed(1)}°`;
    document.getElementById('value-style').textContent = placement?.styles[v.style - 1] || '';
    for (const slider of sliders) {
        const input = numberInputs.get(slider.dataset.key);
        input.min = slider.min; input.max = slider.max; input.step = slider.step;
        if (document.activeElement !== input) {
            input.value = slider.value;
            input.removeAttribute('aria-invalid');
        }
    }
}

function commitNumber(slider) {
    const input = numberInputs.get(slider.dataset.key);
    let value = input.valueAsNumber;
    if (!Number.isFinite(value)) value = Number(slider.value);
    const min = Number(slider.min), max = Number(slider.max), step = Number(slider.step);
    value = Math.max(min, Math.min(max, value));
    value = Math.max(min, Math.min(max, Number((min + Math.round((value - min) / step) * step).toFixed(6))));
    slider.value = String(value);
    input.value = slider.value;
    input.removeAttribute('aria-invalid');
    slider.dispatchEvent(new Event('input'));
}

function commitNumbers() {
    for (const slider of sliders) {
        if (document.activeElement === numberInputs.get(slider.dataset.key)) commitNumber(slider);
    }
}

for (const slider of sliders) {
    const input = numberInputs.get(slider.dataset.key);
    input.addEventListener('input', () => {
        if (!placement || placement.saving || input.disabled) return;
        const value = input.valueAsNumber;
        if (!Number.isFinite(value) || value < Number(slider.min) || value > Number(slider.max)) {
            input.setAttribute('aria-invalid', 'true');
            return;
        }
        slider.value = String(Number((Number(slider.min) + Math.round((value - Number(slider.min)) / Number(slider.step)) * Number(slider.step)).toFixed(6)));
        input.removeAttribute('aria-invalid');
        slider.dispatchEvent(new Event('input'));
    });
    input.addEventListener('change', () => commitNumber(slider));
    input.addEventListener('blur', () => { if (placement && !placement.saving) commitNumber(slider); });
    input.addEventListener('keydown', event => {
        if (event.key === 'Enter') { event.preventDefault(); commitNumber(slider); input.blur(); }
    });
}

function setSaving(saving) {
    if (!placement) return;
    placement.saving = saving;
    for (const input of sliders) input.disabled = saving || (input.dataset.key === 'style' && placement.styles.length < 2);
    for (const slider of sliders) numberInputs.get(slider.dataset.key).disabled = slider.disabled;
    saveButton.disabled = cancelButton.disabled = focusButton.disabled = groundButton.disabled = saving;
    saveButton.textContent = saving ? '保存中…' : '保存する';
}

function closePlacement() {
    clearTimeout(updateTimer); updateTimer = null;
    placement = null;
    placementPanel.classList.add('hidden');
}

window.addEventListener('message', ({ data }) => {
    if (data?.action === 'placementClose') return closePlacement();
    if (data?.action !== 'placementState') return;
    clearTimeout(updateTimer); updateTimer = null;
    placement = { session: data.session, styles: data.styles || [], saving: data.saving, focused: data.focused };
    document.getElementById('placement-title').textContent = ['chair', 'counter'].includes(data.kind) ? '座席の調整' : 'ベッドの調整';
    document.getElementById('placement-location').textContent = `${data.mlo} / ${data.name}`;
    document.getElementById('seat-style').max = Math.max(1, placement.styles.length);
    document.getElementById('seat-height').min = data.heightMin ?? -2;
    document.getElementById('seat-height').max = data.heightMax ?? 2;
    for (const input of sliders) input.value = data.values[input.dataset.key];
    for (const slider of sliders) numberInputs.get(slider.dataset.key).value = slider.value;
    document.getElementById('style-row').classList.remove('hidden');
    document.getElementById('bed-hint').classList.toggle('hidden', placement.styles.length > 1);
    document.getElementById('focus-hint').classList.toggle('hidden', data.focused);
    placementPanel.classList.toggle('viewing', !data.focused);
    placementError.textContent = data.error || '';
    setSaving(data.saving);
    renderValues();
    placementPanel.classList.remove('hidden');
});

for (const input of sliders) {
    input.addEventListener('input', () => {
        if (!placement || placement.saving) return;
        renderValues();
        pendingValues = { session: placement.session, values: values() };
        if (updateTimer) return;
        updateTimer = setTimeout(() => {
            updateTimer = null;
            const payload = pendingValues;
            updateChain = updateChain.catch(() => {}).then(async () => {
                if (placement?.session !== payload.session || placement.saving) return;
                await nuiPost('placementUpdate', payload);
            }).catch(() => {
                if (placement?.session === payload.session) placementError.textContent = 'プレビューを更新できませんでした。もう一度操作してください。';
            });
        }, 50);
    });
}

saveButton.addEventListener('click', async () => {
    if (!placement || placement.saving) return;
    commitNumbers();
    clearTimeout(updateTimer); updateTimer = null;
    const payload = { session: placement.session, values: values() };
    setSaving(true);
    placementError.textContent = '';
    try {
        await updateChain;
        if (placement?.session !== payload.session) return;
        const response = await nuiPost('placementSave', payload);
        const result = await response.json();
        if (!result.ok && placement?.session === payload.session) {
            setSaving(false);
            placementError.textContent = '値を確認して、もう一度保存してください。';
        }
    } catch (_) {
        if (placement?.session === payload.session) {
            setSaving(false);
            placementError.textContent = '保存結果を確認できませんでした。';
        }
    }
});

async function cancelPlacement() {
    if (!placement || placement.saving) return;
    clearTimeout(updateTimer); updateTimer = null;
    const session = placement.session;
    try {
        const response = await nuiPost('placementCancel', { session });
        if ((await response.json()).ok && placement?.session === session) closePlacement();
    } catch (_) { placementError.textContent = '操作できませんでした。もう一度お試しください。'; }
}
cancelButton.addEventListener('click', cancelPlacement);
groundButton.addEventListener('click', async () => {
    if (!placement || placement.saving) return;
    commitNumbers();
    clearTimeout(updateTimer); updateTimer = null;
    const payload = {session: placement.session, values: values()};
    setSaving(true);
    saveButton.textContent = '高さ調整中…';
    try {
        await updateChain;
        const response = await nuiPost('placementGround', payload);
        const result = await response.json();
        if (!result.ok && placement?.session === payload.session) {
            setSaving(false);
            placementError.textContent = '地面を取得できませんでした。近くに移動して試してください。';
        }
    } catch (_) {
        if (placement?.session === payload.session) {
            setSaving(false);
            placementError.textContent = '高さを調整できませんでした。';
        }
    }
});
focusButton.addEventListener('click', async () => {
    if (!placement || placement.saving) return;
    commitNumbers();
    clearTimeout(updateTimer); updateTimer = null;
    const payload = {session: placement.session, values: values()};
    try {
        await updateChain;
        await nuiPost('placementUpdate', payload);
        await nuiPost('placementFocus', {session: payload.session});
    } catch (_) { placementError.textContent = '視点操作に切り替えられませんでした。'; }
});
document.addEventListener('keydown', event => {
    if (!placement) return;
    if (event.key === 'Escape') { event.preventDefault(); cancelPlacement(); }
    if (event.key === 'Alt' && !event.repeat) { event.preventDefault(); focusButton.click(); }
});
