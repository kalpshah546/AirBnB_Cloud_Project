import http from 'k6/http';
import { check } from 'k6';

const base = __ENV.BASE_URL || 'http://localhost:8080';
export const options = { vus: 10, iterations: 20 };
const runId = __ENV.RUN_ID || String(Date.now());

export default function () {
  const key = `e5-${runId}-${__VU}-${__ITER}`;
  const body = JSON.stringify({ listing_id: 123, guest_id: `guest-${__VU}`, check_in: '2027-06-01', check_out: '2027-06-04', guest_count: 2 });
  const params = { headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key } };
  const first = http.post(`${base}/bookings`, body, params);
  const retry = http.post(`${base}/bookings`, body, params);
  check(first, { 'first booking accepted': (r) => r.status === 202 });
  check(retry, { 'retry accepted': (r) => r.status === 202 });
  if (first.status === 202 && retry.status === 202) {
    check(retry.json('booking_id') === first.json('booking_id'), { 'same key returns same booking id': (v) => v });
  }
}
