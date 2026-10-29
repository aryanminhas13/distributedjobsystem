import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';

type Job = { id:string; name:string; status:string; attempts:number; maxAttempts:number; createdAt:string; runAt:string; error?:string };
type Metrics = { queued:number; running:number; completed:number; failed:number; p95DispatchMs:number };
type EventMessage = { job:Job; message:string; at:string };
const active = ['queued','scheduled','running','retrying'];

function App() {
  const [jobs,setJobs] = useState<Job[]>([]);
  const [deadLetters,setDeadLetters] = useState<Job[]>([]);
  const [metrics,setMetrics] = useState<Metrics>({queued:0,running:0,completed:0,failed:0,p95DispatchMs:0});
  const [name,setName] = useState('send-email');
  const [failOnce,setFailOnce] = useState(false);
  const [delay,setDelay] = useState(0);
  const [events,setEvents] = useState<string[]>([]);
  const [filter,setFilter] = useState('all');
  const [refreshing,setRefreshing] = useState(false);
  const [submitting,setSubmitting] = useState(false);
  const [updatedAt,setUpdatedAt] = useState<Date|null>(null);
  const [error,setError] = useState('');
  const [connected,setConnected] = useState(false);
  const [token,setToken] = useState(()=>localStorage.getItem('job-platform-token')||'');

  const authHeaders = token ? {Authorization:`Bearer ${token}`} : {};

  const refresh = async () => {
    setRefreshing(true);
    try {
      const [jobResponse,metricsResponse,dlqResponse] = await Promise.all([fetch('/api/jobs',{cache:'no-store',headers:authHeaders}),fetch('/api/metrics',{cache:'no-store',headers:authHeaders}),fetch('/api/dlq',{cache:'no-store',headers:authHeaders})]);
      if (!jobResponse.ok || !metricsResponse.ok || !dlqResponse.ok) throw new Error('Could not refresh dashboard data');
      setJobs(await jobResponse.json());
      setMetrics(await metricsResponse.json());
      setDeadLetters(await dlqResponse.json());
      setUpdatedAt(new Date());
      setError('');
    } catch (reason) { setError(reason instanceof Error ? reason.message : 'Refresh failed'); }
    finally { setRefreshing(false); }
  };

  useEffect(() => {
    refresh();
    const ws = token ? new WebSocket(`${location.protocol==='https:'?'wss':'ws'}://${location.host}/ws`,`bearer.${token}`) : new WebSocket(`${location.protocol==='https:'?'wss':'ws'}://${location.host}/ws`);
    ws.onopen = () => setConnected(true);
    ws.onclose = () => setConnected(false);
    ws.onerror = () => setConnected(false);
    ws.onmessage = message => {
      const event:EventMessage = JSON.parse(message.data);
      setEvents(current => [`${new Date(event.at).toLocaleTimeString()}  ${event.job.name}: ${event.message}`,...current].slice(0,10));
      refresh();
    };
    const timer = setInterval(refresh,5000);
    return () => { ws.close(); clearInterval(timer); };
  },[]);

  async function submit(event:React.FormEvent) {
    event.preventDefault(); setSubmitting(true); setError('');
    const runAt = delay > 0 ? new Date(Date.now()+delay*1000).toISOString() : undefined;
    try {
      const response = await fetch('/api/jobs',{method:'POST',headers:{'Content-Type':'application/json',...authHeaders,'X-Actor-ID':'dashboard'},body:JSON.stringify({name,payload:{failUntilAttempt:failOnce?1:0},maxAttempts:3,runAt})});
      if (!response.ok) throw new Error((await response.text()).trim() || 'Job submission failed');
      setEvents(current => [`${new Date().toLocaleTimeString()}  ${name}: Submitted`,...current].slice(0,10));
      await refresh();
    } catch (reason) { setError(reason instanceof Error ? reason.message : 'Submission failed'); }
    finally { setSubmitting(false); }
  }

  async function cancel(id:string) {
    const response = await fetch(`/api/jobs/${id}/cancel`,{method:'POST',headers:{...authHeaders,'X-Actor-ID':'dashboard'}});
    if (!response.ok) setError((await response.text()).trim() || 'Cancellation failed');
    await refresh();
  }

  async function replay(id:string) {
    const response = await fetch(`/api/dlq/${id}/replay`,{method:'POST',headers:{...authHeaders,'X-Actor-ID':'dashboard'}});
    if (!response.ok) setError((await response.text()).trim() || 'Replay failed; an administrator token is required');
    await refresh();
  }

  const visibleJobs = useMemo(() => jobs.filter(job => filter==='all'||job.status===filter),[jobs,filter]);
  const metricCards:[string,string][] = [['Queued',String(metrics.queued)],['Running',String(metrics.running)],['Completed',String(metrics.completed)],['Failed',String(metrics.failed)],['p95 dispatch',`${metrics.p95DispatchMs.toFixed(2)} ms`]];

  return <main>
    <header><div><p className="eyebrow">ORCHESTRATOR / LIVE</p><h1>Job control plane</h1><p className="sub">Durable queues, observable execution, resilient workers.</p></div><div className="refresh"><div className={`connection ${connected?'online':'offline'}`}>{connected?'Live':'Reconnecting'}</div><div className="token"><input type="password" aria-label="Access token" placeholder="Access token" value={token} onChange={event=>setToken(event.target.value)}/><button onClick={()=>{localStorage.setItem('job-platform-token',token);location.reload()}}>Use token</button></div><button onClick={refresh} disabled={refreshing}>{refreshing?'Refreshing…':'Refresh'}</button><small>{updatedAt?`Updated ${updatedAt.toLocaleTimeString()}`:'Not refreshed yet'}</small></div></header>
    {error && <div className="error" role="alert">{error}<button onClick={()=>setError('')}>×</button></div>}
    <section className="metrics">{metricCards.map(([label,value])=><article key={label}><span>{label}</span><strong>{value}</strong></article>)}</section>
    <section className="grid"><form onSubmit={submit}><p className="eyebrow">SUBMIT WORK</p><h2>Create a job</h2><label>Job name<input value={name} onChange={event=>setName(event.target.value)} maxLength={120} required/></label><label>Start delay (seconds)<input type="number" min="0" max="86400" value={delay} onChange={event=>setDelay(Number(event.target.value))}/></label><label className="check"><input type="checkbox" checked={failOnce} onChange={event=>setFailOnce(event.target.checked)}/>Fail the first attempt, then recover</label><button className="primary" disabled={submitting}>{submitting?'Submitting…':delay>0?'Schedule job':'Queue job'}</button><p className="hint">Retries use exponential backoff, up to three attempts.</p></form><aside><p className="eyebrow">EVENT STREAM</p><h2>Execution log</h2><div className="logs">{events.length?events.map((entry,index)=><div key={index}>{entry}</div>):<div>Waiting for job events…</div>}</div></aside></section>
    <section className="jobs"><div className="tableHead"><div><p className="eyebrow">QUEUE</p><h2>Recent jobs</h2></div><div className="tableTools"><select value={filter} onChange={event=>setFilter(event.target.value)}><option value="all">All statuses</option>{['queued','scheduled','running','retrying','completed','failed','cancelled'].map(status=><option key={status}>{status}</option>)}</select><span>{visibleJobs.length} shown</span></div></div><div className="table"><div className="row labels"><span>Job</span><span>Status</span><span>Attempts</span><span>Created</span><span></span></div>{visibleJobs.map(job=><div className="row" key={job.id}><span><b>{job.name}</b><small>{job.id.slice(0,8)}</small></span><span className={`badge ${job.status}`}>{job.status}</span><span>{job.attempts} / {job.maxAttempts}</span><span>{new Date(job.createdAt).toLocaleTimeString()}</span><span>{active.includes(job.status)&&<button onClick={()=>cancel(job.id)}>Cancel</button>}</span></div>)}</div></section>
    <section className="jobs"><div className="tableHead"><div><p className="eyebrow">RECOVERY</p><h2>Dead-letter queue</h2></div><div className="tableTools"><span>{deadLetters.length} terminal failures</span></div></div><div className="table"><div className="row labels"><span>Job</span><span>Status</span><span>Attempts</span><span>Error</span><span></span></div>{deadLetters.length?deadLetters.map(job=><div className="row" key={job.id}><span><b>{job.name}</b><small>{job.id.slice(0,8)}</small></span><span className="badge failed">failed</span><span>{job.attempts} / {job.maxAttempts}</span><span>{job.error||'Execution failed'}</span><span><button onClick={()=>replay(job.id)}>Replay</button></span></div>):<div className="empty">No dead-lettered jobs.</div>}</div></section>
  </main>;
}

createRoot(document.getElementById('root')!).render(<App/>);
