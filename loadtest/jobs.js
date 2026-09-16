import http from 'k6/http';
import { check } from 'k6';

// k6 run -e BASE_URL=http://localhost:8080 loadtest/jobs.js
export const options = {
  thresholds: { http_req_failed: ['rate<0.01'], http_req_duration: ['p(95)<150'] },
  scenarios: { submit: { executor: 'constant-arrival-rate', rate: 134, timeUnit: '1s', duration: '13m', preAllocatedVUs: 50, maxVUs: 300 } }
};
export default function () {
  const r = http.post(`${__ENV.BASE_URL || 'http://localhost:8080'}/api/jobs`, JSON.stringify({ name: 'benchmark', payload: { sequence: __ITER, durationMs: 25 }, maxAttempts: 3 }), { headers: { 'Content-Type': 'application/json' } });
  check(r, { accepted: x => x.status === 200 });
}
