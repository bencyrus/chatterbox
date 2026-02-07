import { useCallback } from 'react';
import {
  HiOutlineCheckCircle,
  HiOutlineExclamationTriangle,
  HiOutlineInformationCircle,
  HiOutlineXCircle,
  HiOutlineXMark,
} from 'react-icons/hi2';
import { cn } from '../../lib/cn';
import { useToast } from '../../contexts/ToastContext';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

type ToastVariant = 'default' | 'success' | 'error' | 'warning';

interface ToastData {
  id: string;
  message: string;
  variant: ToastVariant;
}

interface ToastItemProps {
  toast: ToastData;
  onDismiss: (id: string) => void;
}

// ═══════════════════════════════════════════════════════════════════════════
// ICON MAP
// ═══════════════════════════════════════════════════════════════════════════

const iconMap: Record<ToastVariant, React.ReactNode> = {
  default: <HiOutlineInformationCircle className="w-5 h-5" />,
  success: <HiOutlineCheckCircle className="w-5 h-5" />,
  error: <HiOutlineXCircle className="w-5 h-5" />,
  warning: <HiOutlineExclamationTriangle className="w-5 h-5" />,
};

const colorMap: Record<ToastVariant, string> = {
  default: 'bg-app-green-strong text-white',
  success: 'bg-app-green-strong text-white',
  error: 'bg-error-600 text-white',
  warning: 'bg-warning-600 text-white',
};

// ═══════════════════════════════════════════════════════════════════════════
// TOAST ITEM
// ═══════════════════════════════════════════════════════════════════════════

function ToastItem({ toast, onDismiss }: ToastItemProps) {
  const handleDismiss = useCallback(() => {
    onDismiss(toast.id);
  }, [toast.id, onDismiss]);

  return (
    <div
      className={cn(
        'flex items-center gap-3 px-6 py-4 rounded-lg shadow-lg',
        'animate-slide-up',
        'backdrop-blur-sm',
        colorMap[toast.variant]
      )}
      role="alert"
    >
      {/* Icon */}
      <span className="flex-shrink-0">{iconMap[toast.variant]}</span>

      {/* Message */}
      <p className="flex-1 text-body-md font-semibold">{toast.message}</p>

      {/* Dismiss button */}
      <button
        type="button"
        onClick={handleDismiss}
        className="flex-shrink-0 p-1 rounded-full hover:bg-white/20 transition-colors"
        aria-label="Dismiss"
      >
        <HiOutlineXMark className="w-5 h-5" />
      </button>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// TOAST CONTAINER
// ═══════════════════════════════════════════════════════════════════════════

export function ToastContainer() {
  const { toasts, hideToast } = useToast();

  if (toasts.length === 0) {
    return null;
  }

  return (
    <div
      className={cn(
        'fixed bottom-24 left-4 right-4 z-toast',
        'flex flex-col gap-3',
        'max-w-md mx-auto'
      )}
    >
      {toasts.map((toast) => (
        <ToastItem key={toast.id} toast={toast} onDismiss={hideToast} />
      ))}
    </div>
  );
}
