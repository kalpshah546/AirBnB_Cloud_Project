import http from 'k6/http';
import { check } from 'k6';

const base = __ENV.BASE_URL || 'http://localhost:8080';
export const options = {
  scenarios: {
    listing_reads: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RATE || 50),
      timeUnit: '1s',
      duration: __ENV.DURATION || '5m',
      preAllocatedVUs: 50,
      maxVUs: 300,
    },
  },
};

export default function () {
  const id = 1 + (__ITER % 100);
  const response = http.get(`${base}/listings/${id}`, { tags: { experiment: 'E4', route: 'listing' } });
  check(response, { 'listing is 200': (r) => r.status === 200 });
}
