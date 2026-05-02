import http from 'k6/http';

const configPath = __ENV.K6_CONFIG_FILE || '/config-k6/config.json';
const config = JSON.parse(open(configPath));

if (!__ENV.service_url) {
    throw new Error('service_url env var is required');
}

const testDuration = __ENV.duration || config.duration;

if (!testDuration) {
    throw new Error('duration env var or config duration is required');
}

function buildOptions() {
    if (config.mode === 'rps') {
        return {
            scenarios: {
                feed_rps: {
                    executor: 'constant-arrival-rate',
                    rate: Number(config.rps),
                    timeUnit: config.timeUnit || '1s',
                    duration: testDuration,
                    preAllocatedVUs: Number(config.preAllocatedVUs),
                    maxVUs: Number(config.maxVUs),
                },
            },
        };
    }

    return {
        vus: Number(config.vus || 50),
        duration: testDuration,
    };
}

export const options = buildOptions();

const base_url = __ENV.service_url;

export default function () {
    http.get(base_url + '/feed', {
        headers: {
            'X-User-Id': String(__VU),
        },
    });
}
