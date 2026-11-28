const csvPanel=document.createElement('section');
csvPanel.hidden=true;
csvPanel.style.cssText='position:fixed;inset:12% 20%;z-index:100;padding:24px;background:#14202bf5;border:1px solid #67d4bd;border-radius:14px;display:none;font-family:Arial,"Yu Gothic",sans-serif';
csvPanel.innerHTML='<h2>CSV読み込み</h2><p>既存IDは更新、新規IDは追加します。全行の検証に成功した場合だけ保存します。</p><input type="file" accept=".csv,text/csv"><textarea aria-label="CSVデータ" style="width:100%;height:50%;margin:16px 0;color:#fff;background:#09121b"></textarea><p role="status"></p><button type="button">読み込む</button><button type="button">キャンセル</button>';
document.body.append(csvPanel);
const csvText=csvPanel.querySelector('textarea'),csvStatus=csvPanel.querySelector('[role=status]');
const csvButtons=csvPanel.querySelectorAll('button');
function closeCsv(){csvPanel.hidden=true;csvPanel.style.display='none';}
const csvPost=(name,data)=>fetch(`https://${GetParentResourceName()}/${name}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)}).then(r=>r.json());
csvPanel.querySelector('input').onchange=async event=>{const file=event.target.files[0];if(!file)return;if(file.size>2000000){csvStatus.textContent='CSVは2MB以下にしてください。';return;}csvText.value=await file.text();};
csvButtons[0].onclick=async()=>{csvButtons[0].disabled=true;try{const result=await csvPost('csvSubmit',{text:csvText.value});if(result.ok)closeCsv();else csvStatus.textContent=result.message;}catch{csvStatus.textContent='通信に失敗しました。';}finally{csvButtons[0].disabled=false;}};
csvButtons[1].onclick=async()=>{await csvPost('csvCancel',{});closeCsv();};
window.addEventListener('message',({data})=>{
    if(data.action==='csvImport'){csvPanel.hidden=false;csvPanel.style.display='block';csvText.value='';csvStatus.textContent='';csvPanel.querySelector('input').value='';}
    if(data.action==='csvExport'){
        const url=URL.createObjectURL(new Blob(['\ufeff',data.text],{type:'text/csv;charset=utf-8'}));
        const link=document.createElement('a');link.href=url;link.download=data.name;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
    }
});
document.addEventListener('keydown',event=>{if(event.key==='Escape'&&!csvPanel.hidden){event.preventDefault();csvButtons[1].click();}});
