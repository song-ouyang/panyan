import { config } from './config.js';

export function initialModerationStatus(): 'approved' | 'pending' {
  return config.MODERATION_MODE === 'manual' ? 'pending' : 'approved';
}

