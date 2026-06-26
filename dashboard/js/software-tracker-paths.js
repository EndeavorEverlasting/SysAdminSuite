// software-tracker-paths.js — canonical offline workbook + report paths for dashboard tutorials

export const SOFTWARE_TRACKER_PATHS = {
  offlineWorkbook: 'logs/targets/software/Software Tracker 6-26-2026.xlsx',
  offlineWorkbookWindows: 'logs\\targets\\software\\Software Tracker 6-26-2026.xlsx',
  config: 'Config/software-tracker.example.json',
  reportDir: 'survey/output/software-tracker-install',
  reportJson: 'survey/output/software-tracker-install/install-summary.json',
  reportCsv: 'survey/output/software-tracker-install/install-summary.csv',
  reportText: 'survey/output/software-tracker-install/install-log.txt',
};

export function buildSoftwareTrackerDryRunCommand({ list = '', software = '' } = {}) {
  const lines = [
    'bash scripts/sas-software-tracker-install.sh \\',
    `  --tracker "${SOFTWARE_TRACKER_PATHS.offlineWorkbook}" \\`,
    `  --config ${SOFTWARE_TRACKER_PATHS.config}`,
  ];
  if (list) lines.push(`  --list "${list}" \\`);
  if (software) lines.push(`  --software "${software}" \\`);
  if (lines[lines.length - 1].endsWith(' \\')) {
    lines[lines.length - 1] = lines[lines.length - 1].slice(0, -2);
  }
  return lines.join('\n');
}

export function buildSoftwareTrackerExecuteCommand({ list = '', software = '', allowFolder = false } = {}) {
  let cmd = buildSoftwareTrackerDryRunCommand({ list, software });
  cmd += ' \\\n  --execute';
  if (allowFolder) cmd += ' \\\n  --allow-discovered-folder-installs';
  return cmd;
}
