import http from 'k6/http';

const testDuration = __ENV.duration || '2m';

export const options = {
    vus: 50,
    duration: testDuration,
};

const base_url = __ENV.service_url || 'http://localhost:8080';

export default function () {
    const res = http.get(base_url + '/feed', {
        headers: {
            'X-User-Id': String(__VU),
        },
    });
    if (res.status !== 200) {
        console.warn(`HTTP error, status: ${res.status}, body: ${res.body}`);
    }
}
