import { useState, useRef, useEffect, useCallback } from 'react';
import { ArrowsClockwise, Download, CheckCircle } from '@phosphor-icons/react';
import { useTranslation } from 'react-i18next';
import { useUpdateCheck, useApplyUpdateMutation } from '../api/hooks';
import { api } from '../api/endpoints';

type UpdatePhase = 'idle' | 'confirm' | 'downloading' | 'installing' | 'restarting' | 'reconnecting' | 'success' | 'error';

export default function UpdateButton() {
  const { t } = useTranslation();
  const { data: updateInfo } = useUpdateCheck();
  const applyUpdate = useApplyUpdateMutation();
  const [phase, setPhase] = useState<UpdatePhase>('idle');
  const [errorMsg, setErrorMsg] = useState('');
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close dropdown on outside click
  useEffect(() => {
    if (phase !== 'confirm') return;
    function handleClick(e: MouseEvent) {
      if (dropdownRef.current != null && !dropdownRef.current.contains(e.target as Node)) {
        setPhase('idle');
      }
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [phase]);

  // Poll for daemon reconnection after update
  const pollForReconnect = useCallback(async (expectedVersion: string) => {
    setPhase('reconnecting');
    const maxAttempts = 30;
    for (let i = 0; i < maxAttempts; i++) {
      await new Promise((r) => setTimeout(r, 2000));
      try {
        const check = await api.checkUpdate();
        if (check.current_version !== expectedVersion) continue;
        setPhase('success');
        setTimeout(() => setPhase('idle'), 5000);
        return;
      } catch {
        // Daemon not ready yet
      }
    }
    setPhase('error');
    setErrorMsg(t('update.terminalFallback'));
  }, [t]);

  const handleUpdate = useCallback(async () => {
    if (updateInfo?.latest_version == null) return;
    setPhase('downloading');

    try {
      const result = await applyUpdate.mutateAsync();
      if (result.success) {
        setPhase('restarting');
        void pollForReconnect(result.version);
      }
    } catch (e) {
      setPhase('error');
      setErrorMsg(e instanceof Error ? e.message : String(e));
    }
  }, [updateInfo, applyUpdate, pollForReconnect]);

  if (updateInfo == null) return null;

  const currentVersion = updateInfo.current_version;
  const latestVersion = updateInfo.latest_version ?? currentVersion;
  const isUpdating = phase === 'downloading' || phase === 'installing' || phase === 'restarting' || phase === 'reconnecting';

  // Success toast
  if (phase === 'success') {
    return (
      <span className="h-8 px-2.5 inline-flex items-center gap-1.5 rounded-lg text-xs text-green-600 dark:text-green-400">
        <CheckCircle size={16} weight="bold" />
        <span className="font-medium">{t('update.success', { version: latestVersion })}</span>
      </span>
    );
  }

  // Error state
  if (phase === 'error') {
    return (
      <button
        onClick={() => setPhase('idle')}
        className="h-8 px-2.5 inline-flex items-center gap-1.5 rounded-lg text-xs text-red-500 dark:text-red-400 hover:bg-[var(--header-control-hover)] transition-colors cursor-pointer"
        title={errorMsg}
      >
        <span className="font-medium">{t('update.error', { error: errorMsg })}</span>
      </button>
    );
  }

  // Updating spinner
  if (isUpdating) {
    const label =
      phase === 'downloading' ? t('update.downloading') :
      phase === 'installing' ? t('update.installing') :
      phase === 'restarting' ? t('update.restarting') :
      t('update.reconnecting');

    return (
      <span className="h-8 px-2.5 inline-flex items-center gap-1.5 rounded-lg text-xs text-subtle-ui">
        <ArrowsClockwise size={16} className="animate-spin" />
        <span className="font-medium">{label}</span>
      </span>
    );
  }

  // No update available — show quiet version
  if (!updateInfo.update_available) {
    return (
      <span
        className="h-8 px-2.5 inline-flex items-center rounded-lg text-xs text-subtle-ui"
        title={`coast ${currentVersion}`}
      >
        <span className="font-medium">v{currentVersion}</span>
      </span>
    );
  }

  // Update available — button with confirmation dropdown
  return (
    <div ref={dropdownRef} className="relative">
      <button
        onClick={() => setPhase(phase === 'confirm' ? 'idle' : 'confirm')}
        className="h-8 px-2.5 inline-flex items-center gap-1.5 rounded-lg text-xs text-amber-600 dark:text-amber-400 hover:bg-[var(--header-control-hover)] transition-colors cursor-pointer"
        title={`${currentVersion} → ${latestVersion}`}
      >
        <Download size={16} weight="bold" />
        <span className="font-medium">{t('update.available', { version: latestVersion })}</span>
      </button>

      {phase === 'confirm' && (
        <div className="absolute right-0 top-full mt-2 glass-panel p-3 min-w-[240px] z-50">
          <p className="text-sm text-main mb-3">
            {t('update.confirmTitle', { version: latestVersion })}
          </p>
          <div className="flex gap-2 justify-end">
            <button
              onClick={() => setPhase('idle')}
              className="px-3 py-1.5 text-xs rounded-md text-[var(--text-muted)] hover:bg-[var(--surface-muted-hover)] transition-colors cursor-pointer"
            >
              {t('action.cancel')}
            </button>
            <button
              onClick={() => void handleUpdate()}
              className="px-3 py-1.5 text-xs rounded-md bg-amber-600 text-white hover:bg-amber-700 transition-colors cursor-pointer"
            >
              {t('update.confirm')}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
