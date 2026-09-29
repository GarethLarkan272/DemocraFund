// A dismissible error banner used across forms and action surfaces.
export default function ErrorBanner({
  error,
  onDismiss,
}: {
  error: string;
  onDismiss: () => void;
}) {
  return (
    <div className="flex items-start justify-between gap-3 border border-red-200 bg-red-50 rounded-xl px-4 py-3">
      <div className="flex items-start gap-3">
        <span className="mt-0.5 text-red-600">⚠</span>
        <p className="text-red-500 text-sm">{error}</p>
      </div>
      <button
        onClick={onDismiss}
        className="text-red-600 hover:text-red-500 text-sm leading-none px-1"
        aria-label="Dismiss"
      >
        ✕
      </button>
    </div>
  );
}