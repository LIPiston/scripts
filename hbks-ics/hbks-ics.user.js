// ==UserScript==
// @name         HBKS 课表导出 ICS
// @namespace    https://github.com/LIPiston/scripts
// @version      0.7.0
// @description  将河北科师教务系统课表导出为带30分钟提醒的 ICS
// @match        https://jwxt.hevttc.edu.cn/*
// @grant        none
// @run-at       document-idle
// ==/UserScript==

(() => {
  'use strict';
  const DEFAULT_TERM = '2026-2027-1';
  const PERIODS = {
    1:['08:00','09:40'], 3:['10:00','11:40'], 5:['13:30','15:10'],
    7:['15:30','17:10'], 9:['17:30','19:00'], 11:['19:30','21:00']
  };
  const esc = s => String(s || '').replace(/\\/g,'\\\\').replace(/([;,])/g,'\\$1').replace(/\r?\n/g,'\\n');
  const pad = n => String(n).padStart(2,'0');
  const dt = (d, hm) => `${d.getFullYear()}${pad(d.getMonth()+1)}${pad(d.getDate())}T${hm.replace(':','')}00`;
  const parseDate = s => { const d=new Date(`${s}T00:00:00`); return isNaN(d) ? null : d; };
  const addDays = (d,n) => { const x=new Date(d); x.setDate(x.getDate()+n); return x; };
  const monday = d => addDays(d, -((d.getDay()+6)%7));

  function sourceDocument() {
    const frame = document.querySelector('#checkedIframe, iframe.J_iframe');
    try { if (frame && frame.contentDocument && frame.contentDocument.querySelector('td.cell[id^="Cell"]')) return frame.contentDocument; } catch (_) {}
    return document;
  }
  function weeks(s) {
    const out=[];
    const source=String(s||'').match(/[0-9０-９,，\-~～()（）单双]+周/);
    if(!source) return out;
    for (const part of source[0].replace(/周/g,'').replace(/[（）]/g,m=>m==='（'?'(' : ')').split(/[,，]/)) {
      const m=part.trim().match(/^(\d+)(?:-(\d+))?(?:\((单|双)\))?$/); if(!m) continue;
      for(let n=+m[1]; n<=+(m[2]||m[1]); n++) if(!m[3] || (m[3]==='单' ? n%2 : !(n%2))) out.push(n);
    }
    return [...new Set(out)].sort((a,b)=>a-b);
  }
  function parseCell(cell) {
    const id=cell.id.match(/^Cell([1-7])(11|9|7|5|3|1)$/); if(!id) return [];
    const weekday=+id[1], period=+id[2], times=PERIODS[period]; if(!times) return [];
    const text=cell.innerText.replace(/\r/g,'').split('\n').map(x=>x.trim()).filter(Boolean);
    const starts=[]; text.forEach((x,i)=>{ if(['秦皇岛','昌黎','开发区','山东堡','其它'].includes(x)) starts.push(i); });
    return starts.map((start,n)=>{
      const a=text.slice(start, starts[n+1] ?? text.length), wi=a.findIndex(x=>/周$/.test(x));
      if(wi<2) return null;
      const title=a[1], type=/^（.*）$/.test(a[2]||'') ? a[2] : '';
      const weekLine=a[wi], weekMatch=weekLine.match(/[0-9０-９,，\-~～()（）单双]+周/);
      return {weekday,period,times,title:title+type,teacher:weekMatch ? weekLine.slice(0,weekMatch.index).trim() : a[wi-1]||'',weekText:weekMatch ? weekMatch[0] : '',room:a[wi+1]||'',exam:a.slice(wi+2).find(x=>['考试','考查','技术测试'].includes(x))||''};
    }).filter(Boolean);
  }
  function collect(doc) { return [...doc.querySelectorAll('td.cell[id^="Cell"]')].flatMap(parseCell); }
  function download(name, data) { const a=document.createElement('a'); a.href=URL.createObjectURL(new Blob([data],{type:'text/calendar;charset=utf-8'})); a.download=name; a.click(); setTimeout(()=>URL.revokeObjectURL(a.href),1000); }
  function build(courses, firstMonday, calendarName, term) {
    const now=new Date(), L=['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//LIPiston//HBKS ICS//CN','CALSCALE:GREGORIAN',`X-WR-CALNAME:${esc(calendarName)}`,`X-WR-CALDESC:${esc(`学年学期：${term}`)}`,'X-WR-TIMEZONE:Asia/Shanghai'];
    for(const c of courses) for(const w of weeks(c.weekText)) {
      const day=addDays(firstMonday,(w-1)*7+c.weekday-1), [st,et]=c.times;
      const key=`${c.title}|${day.toISOString().slice(0,10)}|${c.room}`;
      L.push('BEGIN:VEVENT',`UID:${encodeURIComponent(key)}@hbks-ics`,`DTSTAMP:${dt(now,'00:00')}Z`,`DTSTART;TZID=Asia/Shanghai:${dt(day,st)}`,`DTEND;TZID=Asia/Shanghai:${dt(day,et)}`,`SUMMARY:${esc(c.title)}`,`LOCATION:${esc(c.room)}`,`DESCRIPTION:${esc(`教师：${c.teacher}；周次：${c.weekText}；类型：${c.exam}`)}`,'BEGIN:VALARM','ACTION:DISPLAY','TRIGGER:-PT30M','DESCRIPTION:课程提醒','END:VALARM','END:VEVENT');
    }
    L.push('END:VCALENDAR'); return L.join('\r\n')+'\r\n';
  }
  function run() {
    let courses=collect(sourceDocument()); if(!courses.length) return alert('未找到课表单元，请打开实际课表 iframe 页面后重试。');
    const opening=prompt('请输入第1周第一天的开学日期（YYYY-MM-DD；例如今年新生为 2026-09-03）：','2026-09-03')?.trim();
    const first=parseDate(opening||''); if(!first) return alert('开学日期格式无效，未导出。');
    const term=prompt('请输入学年学期，例如 2026-2027-1：',DEFAULT_TERM)?.trim();
    if(!term || !/^\d{4}-\d{4}-[12]$/.test(term)) return alert('学年学期格式无效，请使用例如 2026-2027-1。');
    const firstWeek=monday(first);
    const calendarName=`课表${opening.replace(/-/g,'')}`;
    const ics=build(courses,firstWeek,calendarName,term); download(`课表${opening.replace(/-/g,'')}.ics`,ics);
    const count=(ics.match(/BEGIN:VEVENT/g)||[]).length; alert(`已导出 ${count} 个课程事件。每个事件含一个提前30分钟提醒。`);
  }
  const b=document.createElement('button'); b.textContent='导出 ICS'; Object.assign(b.style,{position:'fixed',right:'20px',bottom:'20px',zIndex:999999,padding:'10px 16px',background:'#1677ff',color:'#fff',border:0,borderRadius:'6px',cursor:'pointer',fontSize:'14px'}); b.onclick=run; document.body.appendChild(b);
})();
