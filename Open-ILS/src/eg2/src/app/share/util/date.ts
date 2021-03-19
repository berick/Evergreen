
/* Utility code for dates */

export class DateUtil {

    /**
     * Converts an interval string to seconds.
     *
     * intervalToSeconds('1 min 2 seconds')) => 62
     * intervalToSeconds('2 days')) => 172800 (except across time changes)
     * intervalToSeconds('02:00:23')) => 7223
     */
    static intervalToSeconds(interval: string): number {
        const d = new Date();
        const start = d.getTime();
        const parts = interval.split(' ');

        for (let i = 0; i < parts.length; i += 2)  {

            if (!parts[i + 1]) {
                // interval is a bare hour:min:sec string
                const times = parts[i].split(':');
                d.setHours(d.getHours() + Number(times[0]));
                d.setMinutes(d.getMinutes() + Number(times[1]));
                d.setSeconds(d.getSeconds() + Number(times[2]));
                continue;
            }

            const count = Number(parts[i]);
            const partType = parts[i + 1].replace(/s?,?$/, '');

            if (partType.match(/^s/)) {
                d.setSeconds(d.getSeconds() + count);
            } else if (partType.match(/^min/)) {
                d.setMinutes(d.getMinutes() + count);
            } else if (partType.match(/^h/)) {
                d.setHours(d.getHours() + count);
            } else if (partType.match(/^d/)) {
                d.setDate(d.getDate() + count);
            } else if (partType.match(/^mon/)) {
                d.setMonth(d.getMonth() + count);
            } else if (partType.match(/^y/)) {
                d.setFullYear(d.getFullYear() + count);
            }
        }

        return Number((d.getTime() - start) / 1000);
    }

    // Create a date in the local time zone with selected YMD values.
    static localDateFromYmd(ymd: string): Date {
        const parts = ymd.split('-');
        return new Date(
            Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    }
}

