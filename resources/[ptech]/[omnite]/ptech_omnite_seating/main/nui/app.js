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
