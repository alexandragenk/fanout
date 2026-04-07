import http from 'k6/http';

export const options = {
    vus: 16,
    duration: '1m',
};

export default function () {
    http.get('http://localhost:8080/feed', {
        headers: {
            'X-User-Id': String(__VU),
        },
    });
}