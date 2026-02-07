import { HiOutlineMicrophone } from 'react-icons/hi2';
import { Button } from '../ui/Button';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface NewRecordingButtonProps {
  onClick: () => void;
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW RECORDING BUTTON
// ═══════════════════════════════════════════════════════════════════════════

export function NewRecordingButton({ onClick }: NewRecordingButtonProps) {
  return (
    <Button
      variant="primary"
      size="lg"
      onClick={onClick}
      className="!bg-app-green-strong !text-white hover:!bg-app-green-deep !rounded-full"
      leftIcon={<HiOutlineMicrophone className="w-5 h-5" />}
    >
      New Recording
    </Button>
  );
}
