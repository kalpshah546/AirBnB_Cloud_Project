import http from 'k6/http';
import { check } from 'k6';

const base = __ENV.BASE_URL || 'http://localhost:8080';
const monolith = (__ENV.USE_MONOLITH || 'false').toLowerCase() === 'true';
const prefix = monolith ? '/monolith' : '';

export const options = {
  scenarios: {
    search_blast: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: 100,
      maxVUs: 600,
      stages: [
        { target: 100, duration: '2m' },
        { target: 100, duration: '8m' },
        { target: 10, duration: '1m' },
      ],
    },
    booking_probe: {
      executor: 'constant-arrival-rate',
      rate: 2,
      timeUnit: '1s',
      duration: '11m',
      preAllocatedVUs: 10,
      maxVUs: 30,
      exec: 'bookingProbe',
    },
  },
};

export default function () {
  const response = http.get(`${base}${prefix}/search?city=Goa&limit=20`, { tags: { experiment: 'E3', route: 'search' } });
  check(response, { 'search responds': (r) => r.status === 200 });
}

export function bookingProbe() {
  const key = `e3-${monolith ? 'mono' : 'soa'}-${__VU}-${__ITER}-${Date.now()}`;
  const response = http.post(
    `${base}${prefix}/bookings`,
    JSON.stringify({ listing_id: 42, guest_id: `probe-${__VU}`, check_in: '2027-05-01', check_out: '2027-05-03', guest_count: 1 }),
    { headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key }, tags: { experiment: 'E3', route: 'booking' } },
  );
  check(response, { 'booking probe accepted': (r) => r.status === 202 });
}
