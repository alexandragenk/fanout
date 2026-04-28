import http from 'k6/http';

export const options = {
    stages: [
        { duration: '2m', target: 50 }
    ],
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