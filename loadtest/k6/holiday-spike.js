import http from 'k6/http';
import { check } from 'k6';

const base = __ENV.BASE_URL || 'http://localhost:8080';
const searchWeight = Number(__ENV.SEARCH_WEIGHT || 70);
const listingWeight = Number(__ENV.LISTING_WEIGHT || 20);

export const options = {
  scenarios: {
    holiday_traffic: {
      executor: 'ramping-arrival-rate',
      startRate: Number(__ENV.NORMAL_RPS || 20),
      timeUnit: '1s',
      preAllocatedVUs: Number(__ENV.PREALLOCATED_VUS || 120),
      maxVUs: Number(__ENV.MAX_VUS || 1200),
      stages: [
        { target: Number(__ENV.NORMAL_RPS || 20), duration: '30s' },
        { target: Number(__ENV.PEAK_RPS || 200), duration: '2m' },
        { target: Number(__ENV.PEAK_RPS || 200), duration: '15m' },
        { target: Number(__ENV.NORMAL_RPS || 20), duration: '2m' },
        { target: Number(__ENV.NORMAL_RPS || 20), duration: '1m' },
      ],
    },
  },
};

export default function () {
  const draw = Math.random() * 100;
  if (draw < searchWeight) {
    const response = http.get(`${base}/search?city=Goa&limit=20`, { tags: { experiment: 'E2', route: 'search' } });
    check(response, { 'search is 200': (r) => r.status === 200 });
  } else if (draw < searchWeight + listingWeight) {
    const id = 1 + Math.floor(Math.random() * 50000);
    const response = http.get(`${base}/listings/${id}`, { tags: { experiment: 'E2', route: 'listing' } });
    check(response, { 'listing is 200': (r) => r.status === 200 });
  } else {
    const key = `e2-${__VU}-${__ITER}-${Date.now()}`;
    const response = http.post(
      `${base}/bookings`,
      JSON.stringify({ listing_id: 1 + Math.floor(Math.random() * 50000), guest_id: `guest-${__VU}`, check_in: '2027-05-01', check_out: '2027-05-03', guest_count: 2 }),
      { headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key }, tags: { experiment: 'E2', route: 'booking' } },
    );
    check(response, { 'booking accepted': (r) => r.status === 202 });
  }
}
