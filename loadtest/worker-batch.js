import http from 'k6/http';
import { check } from 'k6';

const jobs = Number(__ENV.JOBS || 4000);

export const options = {
  scenarios: {
    preload: {
      executor: 'shared-iterations',
      vus: 50,
      iterations: jobs,
      maxDuration: '2m',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const response = http.post(
    `${__ENV.BASE_URL || 'http://host.docker.internal:8080'}/api/jobs`,
    JSON.stringify({
      name: `scaling-${__ENV.WORKERS || 'unknown'}-workers`,
      payload: { durationMs: 25 },
      maxAttempts: 1,
    }),
    { headers: { 'Content-Type': 'application/json' } },
  );

  check(response, { accepted: (result) => result.status === 200 });
}
