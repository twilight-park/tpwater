<script>
        function truncateText(button, endChars = 5) {
            let fullText = button.textContent;

            function truncate() {
                const maxWidth = button.offsetWidth;
                const textWidth = getTextWidth(fullText, getComputedStyle(button).font);

                if (textWidth <= maxWidth) {
                    button.textContent = fullText;
                    return;
                }

                const endText = fullText.slice(-endChars);
                let startText = fullText.slice(0, -endChars);
                let truncated = startText + '...' + endText;

                while (getTextWidth(truncated, getComputedStyle(button).font) > maxWidth && startText.length > 0) {
                    startText = startText.slice(0, -1);
                    truncated = startText + '...' + endText;
                }

                button.textContent = truncated;
            }

            function getTextWidth(text, font) {
                const canvas = getTextWidth.canvas || (getTextWidth.canvas = document.createElement("canvas"));
                const context = canvas.getContext("2d");
                context.font = font;
                return context.measureText(text).width;
            }

            // Set up MutationObserver to watch for text changes
            const observer = new MutationObserver(() => {
                const newText = button.textContent;
                if (newText !== fullText) {
                    fullText = newText;
                    truncate();
                }
            });

            observer.observe(button, { childList: true, characterData: true, subtree: true });

            // Handle window resize
            window.addEventListener('resize', truncate);

            // Initial truncation
            truncate();

            // Return a function to stop observing (if needed)
            return () => {
                observer.disconnect();
                window.removeEventListener('resize', truncate);
            };
        }

        window.truncateText = truncateText;
    </script>
