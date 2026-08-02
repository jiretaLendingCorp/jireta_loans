// supabase/functions/_shared/rbac.ts
import { errorResponse } from './cors.ts';
import type { AuthUser } from './auth.ts';

export const ROLES = {
  HEAD_MANAGER: 'head_manager',
  EMPLOYEE: 'employee',
  RIDER: 'rider',
  LENDER: 'lender',
} as const;

export function requireRole(user: AuthUser, ...allowedRoles: string[]): Response | null {
  if (!allowedRoles.includes(user.role)) {
    return errorResponse(
      `Access denied. Required role: ${allowedRoles.join(' or ')}`,
      403,
      'FORBIDDEN'
    );
  }
  return null;
}

export function isHeadManager(user: AuthUser): boolean {
  return user.role === ROLES.HEAD_MANAGER;
}

export function isEmployee(user: AuthUser): boolean {
  return user.role === ROLES.EMPLOYEE;
}

export function isRider(user: AuthUser): boolean {
  return user.role === ROLES.RIDER;
}

export function isLender(user: AuthUser): boolean {
  return user.role === ROLES.LENDER;
}

export function isStaff(user: AuthUser): boolean {
  return user.role === ROLES.HEAD_MANAGER || user.role === ROLES.EMPLOYEE;
}

export const enforceRole = requireRole;