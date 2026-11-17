// Search-only traffic spike for the autoscaling demonstration (E2).
// Used when listing/booking ASGs are off (vCPU quota). Stage lengths are env-configurable.
import http from 'k6/http';
import { check } from 'k6';

const base = __ENV.BASE_URL || 'http://localhost:8080';
const normal = Number(__ENV.NORMAL_RPS || 5);
const peak = Number(__ENV.PEAK_RPS || 40);
const sec = (name, dflt) => `${Number(__ENV[name] || dflt)}s`;

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: normal,
      timeUnit: '1s',
      preAllocatedVUs: Number(__ENV.PREALLOCATED_VUS || 60),
      maxVUs: Number(__ENV.MAX_VUS || 400),
      stages: [
        { target: normal, duration: sec('WARM_S', 60) },
        { target: peak, duration: sec('RAMP_S', 60) },
        { target: peak, duration: sec('HOLD_S', 600) },
        { target: normal, duration: sec('DOWN_S', 60) },
        { target: normal, duration: sec('COOL_S', 60) },
      ],
    },
  },
};

export default function () {
  const r = http.get(`${base}/search?city=Goa&max_price=8000&min_rating=3.5&limit=20`, { tags: { experiment: 'E2', route: 'search' } });
  check(r, { 'search returns 200': (x) => x.status === 200 });
}
