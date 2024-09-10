function formatRelativeTime(unixTimestamp) {
    const now = Math.floor(Date.now() / 1000);
    const diff = now - unixTimestamp;

    const breakpoints = [
        [60, '%d seconds ago'],
        [3600, '%d minutes ago'],
        [86400, '%d hours ago'],
        [172800, 'yesterday'],
        [604800, '%d days ago'],
        [2592000, '%d weeks ago'],
        [31536000, '%d months ago']
    ];

    for (const [seconds, format] of breakpoints) {
        if (diff < seconds) {
            if (format.includes('%d')) {
                const value = Math.floor(diff / (seconds / breakpoints[0][0]));
                return format.replace('%d', value);
            } else {
                return format;
            }
        }
    }

    return new Date(unixTimestamp * 1000).toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric'
    });
}
