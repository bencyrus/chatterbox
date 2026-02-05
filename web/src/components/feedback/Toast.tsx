import { useEffect, useCallback } from 'react';
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

type ToastType = 'success' | 'error' | 'warning' | 'info';

interface ToastData {
  id: string;
  message: string;
  type: ToastType;
}

interface ToastItemProps {
  toast: ToastData;
  onDismiss: (id: string) => void;
}

// ═══════════════════════════════════════════════════════════════════════════
// ICON MAP
// ═══════════════════════════════════════════════════════════════════════════

const iconMap: Record<ToastType, React.ReactNode> = {
  success: <HiOutlineCheckCircle className="w-5 h-5" />,
  error: <HiOutlineXCircle className="w-5 h-5" />,
  warning: <HiOutlineExclamationTriangle className="w-5 h-5" />,
  info: <HiOutlineInformationCircle className="w-5 h-5" />,
};

const colorMap: Record<ToastType, string> = {
  success: 'bg-status-success text-white',
  error: 'bg-status-error text-white',
  warning: 'bg-status-warning text-white',
  info: 'bg-brand-primary text-white',
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
        'flex items-center gap-3 px-4 py-3 rounded-lg shadow-modal',
        'animate-slide-up',
        colorMap[toast.type]
      )}
      role="alert"
    >
      {/* Icon */}
      <span className="flex-shrink-0">{iconMap[toast.type]}</span>

      {/* Message */}
      <p className="flex-1 text-body-sm font-medium">{toast.message}</p>

      {/* Dismiss button */}
      <button
        type="button"
        onClick={handleDismiss}
        className="flex-shrink-0 p-1 rounded-full hover:bg-white/20 transition-colors"
        aria-label="Dismiss"
      >
        <HiOutlineXMark className="w-4 h-4" />
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
        'flex flex-col gap-2',
        'max-w-md mx-auto',
        'pointer-events-none'
      )}
    >
      {toasts.map((toast) => (
        <div key={toast.id} className="pointer-events-auto">
          <ToastItem toast={toast} onDismiss={hideToast} />
        </div>
      ))}
    </div>
  );
}
