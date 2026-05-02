import http from 'k6/http';

if (!__ENV.duration) {
    throw new Error('duration env var is required');
}

if (!__ENV.service_url) {
    throw new Error('service_url env var is required');
}

const testDuration = __ENV.duration;

export const options = {
    vus: 50,
    duration: testDuration,
};

const base_url = __ENV.service_url;

export default function () {
    http.get(base_url + '/feed', {
        headers: {
            'X-User-Id': String(__VU),
        },
    });
}
