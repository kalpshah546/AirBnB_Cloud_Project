import http from 'k6/http';
import { check } from 'k6';

const base = __ENV.BASE_URL || 'http://localhost:8080';
const maxRate = Number(__ENV.RATE_MAX || 100);

export const options = {
  scenarios: {
    increasing_search_load: {
      executor: 'ramping-arrival-rate',
      startRate: Number(__ENV.START_RATE || 5),
      timeUnit: '1s',
      preAllocatedVUs: Number(__ENV.PREALLOCATED_VUS || 50),
      maxVUs: Number(__ENV.MAX_VUS || 500),
      stages: [
        { target: Math.max(10, Math.floor(maxRate * 0.25)), duration: '60s' },
        { target: Math.max(20, Math.floor(maxRate * 0.50)), duration: '60s' },
        { target: Math.max(30, Math.floor(maxRate * 0.75)), duration: '60s' },
        { target: maxRate, duration: '60s' },
        { target: maxRate, duration: '120s' },
      ],
    },
  },
};

export default function () {
  const response = http.get(`${base}/search?city=Goa&max_price=8000&min_rating=3.5&limit=20`, {
    tags: { experiment: 'E1', route: 'search' },
  });
  check(response, { 'search returns 200': (r) => r.status === 200 });
}
