import { useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import {
  HiOutlineArrowRightOnRectangle,
  HiOutlineTrash,
  HiOutlineShieldCheck,
} from 'react-icons/hi2';
import { PageHeader } from '../components/layout/PageHeader';
import { Modal, ModalFooter } from '../components/ui/Modal';
import { Button } from '../components/ui/Button';
import {
  SettingsSection,
  SettingsRow,
  LanguageSelector,
  AccountInfo,
} from '../components/settings';
import { useAuth } from '../contexts/AuthContext';
import { useProfile } from '../contexts/ProfileContext';
import { useSettings } from '../hooks/settings/useSettings';
import { ROUTES } from '../lib/constants';

// ═══════════════════════════════════════════════════════════════════════════
// SETTINGS PAGE
// ═══════════════════════════════════════════════════════════════════════════

function SettingsPage() {
  const { account } = useAuth();
  const { activeProfile } = useProfile();
  const {
    changeLanguage,
    isChangingLanguage,
    logout,
    isLoggingOut,
    deleteAccount,
    isDeletingAccount,
  } = useSettings();

  const [loadingLanguage, setLoadingLanguage] = useState<string | null>(null);
  const [showLogoutModal, setShowLogoutModal] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle language select
  // ─────────────────────────────────────────────────────────────────────────

  const handleLanguageSelect = useCallback(async (languageCode: string) => {
    if (languageCode === activeProfile?.languageCode) return;
    
    setLoadingLanguage(languageCode);
    await changeLanguage(languageCode);
    setLoadingLanguage(null);
  }, [activeProfile?.languageCode, changeLanguage]);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle logout
  // ─────────────────────────────────────────────────────────────────────────

  const handleLogout = useCallback(async () => {
    await logout();
    setShowLogoutModal(false);
  }, [logout]);

  // ─────────────────────────────────────────────────────────────────────────
  // Handle delete account
  // ─────────────────────────────────────────────────────────────────────────

  const handleDeleteAccount = useCallback(async () => {
    await deleteAccount();
    setShowDeleteModal(false);
  }, [deleteAccount]);

  // ─────────────────────────────────────────────────────────────────────────
  // Render
  // ─────────────────────────────────────────────────────────────────────────

  return (
    <div>
      <PageHeader title="Settings" />

      <div className="container-page py-6 space-y-8">
        {/* Account section */}
        <SettingsSection title="Account">
          <AccountInfo account={account} />
        </SettingsSection>

        {/* Language section */}
        <SettingsSection
          title="Language"
          description="Select the language you want to practice"
        >
          <LanguageSelector
            selectedLanguage={activeProfile?.languageCode || null}
            onSelect={handleLanguageSelect}
            isLoading={isChangingLanguage}
            loadingLanguage={loadingLanguage}
          />
        </SettingsSection>

        {/* Legal section */}
        <SettingsSection title="Legal">
          <Link to={ROUTES.PRIVACY}>
            <SettingsRow
              icon={<HiOutlineShieldCheck className="w-5 h-5" />}
              label="Privacy Policy"
            />
          </Link>
        </SettingsSection>

        {/* Account actions */}
        <SettingsSection title="Account Actions">
          <SettingsRow
            icon={<HiOutlineArrowRightOnRectangle className="w-5 h-5" />}
            label="Sign out"
            onClick={() => setShowLogoutModal(true)}
            showChevron={false}
          />
          <SettingsRow
            icon={<HiOutlineTrash className="w-5 h-5" />}
            label="Delete account"
            onClick={() => setShowDeleteModal(true)}
            showChevron={false}
            danger
          />
        </SettingsSection>

        {/* App version */}
        <div className="text-center pt-8 pb-4">
          <p className="text-body-sm text-text-tertiary">
            Chatterbox Web v1.0.0
          </p>
        </div>
      </div>

      {/* Logout confirmation modal */}
      <Modal
        isOpen={showLogoutModal}
        onClose={() => setShowLogoutModal(false)}
        title="Sign out?"
      >
        <p className="text-body-md text-text-secondary">
          You'll need to sign in again to access your recordings and practice.
        </p>
        <ModalFooter>
          <Button
            variant="secondary"
            onClick={() => setShowLogoutModal(false)}
          >
            Cancel
          </Button>
          <Button
            variant="primary"
            onClick={handleLogout}
            isLoading={isLoggingOut}
          >
            Sign out
          </Button>
        </ModalFooter>
      </Modal>

      {/* Delete account confirmation modal */}
      <Modal
        isOpen={showDeleteModal}
        onClose={() => setShowDeleteModal(false)}
        title="Delete account?"
      >
        <p className="text-body-md text-text-secondary">
          This will permanently delete your account, all your recordings, and
          practice history. This action cannot be undone.
        </p>
        <ModalFooter>
          <Button
            variant="secondary"
            onClick={() => setShowDeleteModal(false)}
          >
            Cancel
          </Button>
          <Button
            variant="danger"
            onClick={handleDeleteAccount}
            isLoading={isDeletingAccount}
          >
            Delete account
          </Button>
        </ModalFooter>
      </Modal>
    </div>
  );
}

export default SettingsPage;
