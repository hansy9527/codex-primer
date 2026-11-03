'use strict';
(() => {
  const list=$('primer-records'), message=$('primer-message'), refresh=$('primer-refresh'), run=$('primer-run');
  let latest=null, loading=false, acting=false;
  function text(tag,value,parent,cls) { const node=document.createElement(tag);node.textContent=value??'—';if(cls)node.className=cls;parent.append(node);return node; }
  function scheduleEnabled() { return latest?.timer.ActiveState==='active'; }
  function buttons() { const toggle=$('primer-toggle');toggle.disabled=loading||acting||!latest;toggle.setAttribute('aria-checked',String(scheduleEnabled()));toggle.textContent='自动定时运行 · '+(!latest?'尚未读取':scheduleEnabled()?'已开启':'已关闭'); refresh.disabled=loading||acting;run.disabled=loading||acting||!latest||latest.running; }
  function render() {
    const last=latest?.last;
    $('primer-state').textContent=!latest?'尚未读取':latest.running?'正在运行':last?.result==='failure'?'最近执行失败':'空闲';
    $('primer-state').className='badge '+(latest?.running?'warning':last?.result==='success'?'enabled':'');
    $('primer-model').textContent=latest?.config.MODEL||'—';
    $('primer-schedule').textContent=latest?`${latest.config.SCHEDULE_TIMES||'读取失败'} · ${latest.config.APP_TZ||''}`:'—';
    $('primer-next').textContent=latest?.timer.NextElapseUSecRealtime||'—';
    $('primer-timer').textContent=latest?latest.timer.ActiveState==='active'?'定时任务已开启':'定时任务未运行':'—';
    list.replaceChildren();
    if(!latest?.records.length)text('p',latest?'暂无执行记录':'点击“刷新 Primer”读取状态和历史记录。',list);
    for(const record of latest?.records||[]) {
      const row=document.createElement('article');row.className='primer-record';list.append(row);
      const info=document.createElement('div');row.append(info);
      text('strong',(record.result==='success'?'成功':'失败')+' · '+(record.started||record.id),info);
      text('span',`时段 ${record.slot} · ${record.model} · 尝试 ${record.attempts}/${record.max_attempts} · 退出码 ${record.exit_code}`,info,'app-description');
      text('span','完成：'+(record.finished||'—'),info,'app-description');
      if(record.reason)text('p',record.reason,info,'form-error');
      const actions=document.createElement('div');actions.className='primer-record-actions';row.append(actions);
      const log=text('button','查看日志',actions,'secondary');log.disabled=loading||acting;
      log.addEventListener('click',()=>showLog(record));
      if(record.result==='failure') {
        const retry=text('button','重试',actions,'secondary');retry.disabled=loading||acting||latest.running;
        retry.addEventListener('click',()=>execute(record.id));
      }
    }
    buttons();
  }
  async function load(keepMessage=false) {
    if(!authenticated||loading||acting||document.hidden)return;
    loading=true;render();
    try {latest=await api('primer');if(!keepMessage)message.textContent='更新于 '+new Date(latest.checkedAt*1000).toLocaleTimeString('zh-CN')+' · shandun';}
    catch(error){latest=null;message.textContent=error.message;}
    finally{loading=false;render();}
  }
  async function showLog(record) {
    if(loading||acting)return;
    loading=true;buttons();
    $('primer-log-title').textContent='执行日志 · '+record.id;$('primer-log').textContent='正在读取…';
    $('primer-log-panel').showModal();
    try {const result=await api('primer/log?id='+encodeURIComponent(record.id));$('primer-log').textContent=result.log;}
    catch(error){$('primer-log').textContent=error.message;}
    finally{loading=false;buttons();}
  }
  async function execute(id=null) {
    if(!latest||latest.running||loading||acting)return;
    acting=true;render();
    try {
      if(!await confirmClose(id?'重试这条失败记录？':'运行 Codex Primer？','将在 shandun 上使用当前配置发起一次模型请求，消耗对应额度，并在完成后按原配置发送结果通知。','确认执行'))return;
      const result=await api(id?'primer/retry':'primer/run',id?{id}:{});
      message.textContent=result.message;
      if(latest)latest.running=true;
    } catch(error){message.textContent=error.message;}
    finally{acting=false;render();}
  }
  $('primer-toggle').addEventListener('click',async()=>{
    if(!latest||loading||acting)return;
    const enabled=!scheduleEnabled();acting=true;render();
    try {
      if(!await confirmClose(enabled?'开启自动定时运行？':'关闭自动定时运行？',enabled?'恢复按每日计划执行 Codex Primer。':'停止后续定时触发；当前任务会继续完成，手动执行和历史日志仍可使用。',enabled?'确认开启':'确认关闭'))return;
      latest=await api('primer/schedule',{enabled});message.textContent=latest.message;
    }catch(error){message.textContent=error.message;}
    finally{acting=false;render();}
  });
  refresh.addEventListener('click',()=>load());run.addEventListener('click',()=>execute());
  $('primer-log-close').addEventListener('click',()=>{$('primer-log-panel').close();});
  $('primer-log-panel').addEventListener('close',()=>{$('primer-log').textContent='';});
  MediaTabs.register('primer',()=>load(),()=>{latest=null;$('primer-log').textContent='';if($('primer-log-panel').open)$('primer-log-panel').close();message.textContent='点击“刷新 Primer”读取状态';render();});
  render();
})();
