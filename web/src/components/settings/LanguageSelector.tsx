import { useState } from 'react';
import { HiChevronDown, HiOutlineCheck } from 'react-icons/hi2';
import { Card, CardContent } from '../ui/Card';
import { Modal, ModalFooter } from '../ui/Modal';
import { Button } from '../ui/Button';
import { Spinner } from '../ui/Spinner';
import { cn } from '../../lib/cn';
import { getFlagEmoji, getLanguageDisplayName } from '../../lib/languages';
import { useAvailableLanguages } from '../../contexts/ConfigContext';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

interface LanguageSelectorProps {
  /** Current selected language */
  selectedLanguage: string | null;
  /** On language select */
  onSelect: (language: string) => void;
  /** Whether selection is loading */
  isLoading?: boolean;
  /** Language currently being loaded */
  loadingLanguage?: string | null;
  /** Additional class names */
  className?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
// LANGUAGE SELECTOR
// ═══════════════════════════════════════════════════════════════════════════

export function LanguageSelector({
  selectedLanguage,
  onSelect,
  isLoading = false,
  loadingLanguage = null,
  className,
}: LanguageSelectorProps) {
  const availableLanguages = useAvailableLanguages();
  const [showPicker, setShowPicker] = useState(false);

  if (availableLanguages.length === 0) {
    return (
      <Card className={className}>
        <CardContent className="py-6 text-center">
          <p className="text-body-md text-text-secondary">
            No languages available
          </p>
        </CardContent>
      </Card>
    );
  }

  const currentLanguage = selectedLanguage || availableLanguages[0];
  const currentFlag = getFlagEmoji(currentLanguage);
  const currentName = getLanguageDisplayName(currentLanguage);

  const handleSelect = (language: string) => {
    onSelect(language);
    setShowPicker(false);
  };

  return (
    <>
      {/* Dropdown trigger button */}
      <button
        type="button"
        onClick={() => setShowPicker(true)}
        disabled={isLoading}
        className={cn(
          'w-full flex items-center gap-3 px-4 py-3',
          'bg-app-beige rounded-xl',
          'hover:bg-app-beige-hover transition-colors',
          'text-left',
          'disabled:opacity-50 disabled:cursor-not-allowed',
          className
        )}
      >
        {/* Flag emoji */}
        <span className="text-[28px] leading-none">{currentFlag}</span>

        {/* Language name */}
        <span className="flex-1 text-body-md font-medium text-text-primary">
          {currentName}
        </span>

        {/* Chevron or spinner */}
        {isLoading && loadingLanguage ? (
          <Spinner size="sm" />
        ) : (
          <HiChevronDown className="w-5 h-5 text-text-secondary" />
        )}
      </button>

      {/* Language picker modal */}
      <Modal
        isOpen={showPicker}
        onClose={() => setShowPicker(false)}
        title="Select Language"
      >
        <div className="space-y-2 max-h-96 overflow-y-auto">
          {availableLanguages.map((language) => {
            const isSelected = language === selectedLanguage;
            const flag = getFlagEmoji(language);
            const name = getLanguageDisplayName(language);

            return (
              <button
                key={language}
                type="button"
                onClick={() => handleSelect(language)}
                disabled={isLoading}
                className={cn(
                  'w-full flex items-center gap-3 px-4 py-3 rounded-xl transition-colors',
                  isSelected
                    ? 'bg-app-beige-dark border-2 border-app-blue-dark'
                    : 'bg-app-beige hover:bg-app-beige-hover',
                  'disabled:opacity-50 disabled:cursor-not-allowed'
                )}
              >
                {/* Flag emoji */}
                <span className="text-[28px] leading-none">{flag}</span>

                {/* Language name */}
                <span className="flex-1 text-left text-body-md font-medium text-text-primary">
                  {name}
                </span>

                {/* Checkmark if selected */}
                {isSelected && (
                  <HiOutlineCheck className="w-5 h-5 text-app-blue-dark" />
                )}
              </button>
            );
          })}
        </div>

        <ModalFooter>
          <Button variant="secondary" onClick={() => setShowPicker(false)}>
            Close
          </Button>
        </ModalFooter>
      </Modal>
    </>
  );
}
