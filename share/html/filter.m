
function filterNoisySpikes(data, threshold = 35, windowSize = 10, minRemoveCount = 1, maxRemoveCount = 5, fallbackValue = null) {
    function medianOfThree(a, b, c) {
        return [a, b, c].sort((x, y) => x - y)[1];
    }

    return data.map((sample, index, array) => {
        const [timestamp, value, constant] = sample;

        if (index < windowSize || index >= array.length - windowSize) {
            return sample; // Keep edge values unchanged
        }

        const leftWindowSize = Math.min(index, windowSize);
        const rightWindowSize = Math.min(array.length - index - 1, windowSize);

        const leftWindow = array.slice(index - leftWindowSize, index).map(s => s[1]);
        const rightWindow = array.slice(index + 1, index + rightWindowSize + 1).map(s => s[1]);

        // Use minimum for spike detection
        const leftMin = Math.min(...leftWindow);
        const rightMin = Math.min(...rightWindow);
        const baselineEstimate = Math.min(leftMin, rightMin);

        if (value > baselineEstimate + threshold) {
            // This is a spike, determine the extent
            let leftRemoveCount = 0;
            for (let i = index - 1; i >= Math.max(0, index - maxRemoveCount); i--) {
                if (array[i][1] <= baselineEstimate + threshold) break;
                leftRemoveCount++;
            }

            let rightRemoveCount = 0;
            for (let i = index + 1; i < Math.min(array.length, index + maxRemoveCount + 1); i++) {
                if (array[i][1] <= baselineEstimate + threshold) break;
                rightRemoveCount++;
            }

            const removeCount = Math.max(minRemoveCount, leftRemoveCount, rightRemoveCount);

            // Calculate replacement value using median of three
            const leftMedian = medianOfThree(
                leftWindow[Math.floor(leftWindow.length / 4)],
                leftWindow[Math.floor(leftWindow.length / 2)],
                leftWindow[Math.floor(3 * leftWindow.length / 4)]
            );
            const rightMedian = medianOfThree(
                rightWindow[Math.floor(rightWindow.length / 4)],
                rightWindow[Math.floor(rightWindow.length / 2)],
                rightWindow[Math.floor(3 * rightWindow.length / 4)]
            );
            let replacementValue = (leftMedian + rightMedian) / 2;

            // Fallback options if median calculation fails
            if (isNaN(replacementValue)) {
                if (index === 0 && fallbackValue !== null) {
                    replacementValue = fallbackValue;
                } else {
                    replacementValue = baselineEstimate;
                }
            }

            // Replace spike and surrounding values
            for (let i = Math.max(0, index - removeCount); i <= Math.min(array.length - 1, index + removeCount); i++) {
                array[i] = [array[i][0], replacementValue, array[i][2]];
            }

            return [timestamp, replacementValue, constant];
        }

        return sample; // Return original sample if not a spike
    });
}

