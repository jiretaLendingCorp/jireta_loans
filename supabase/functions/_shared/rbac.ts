// supabase/functions/_shared/rbac.ts
import type { AuthUser } from './auth.ts';
import { errorResponse } from './cors.ts';

export const ROLES = {
  HEAD_MANAGER: 'head_manager',
  EMPLOYEE: 'employee',
  RIDER: 'rider',
  LENDER: 'lender',
} as const;

// Module → allowed roles mapping used by checkPermission().
// Extend this object as new modules are added.
const MODULE_PERMISSIONS: Record<string, Record<string, string[]>> = {
  in_office: {
    submit: [ROLES.HEAD_MANAGER, ROLES.EMPLOYEE],
    create:  [ROLES.HEAD_MANAGER, ROLES.EMPLOYEE],
    list:    [ROLES.HEAD_MANAGER, ROLES.EMPLOYEE],
    save:    [ROLES.HEAD_MANAGER, ROLES.EMPLOYEE],
  },
  kyc: {
    verify: [ROLES.HEAD_MANAGER, ROLES.EMPLOYEE],
    list:   [ROLES.HEAD_MANAGER, ROLES.EMPLOYEE],
  },
  loans: {
    approve: [ROLES.HEAD_MANAGER],
    reject:  [ROLES.HEAD_MANAGER],
    apply:   [ROLES.LENDER],
    list:    [ROLES.HEAD_MANAGER, ROLES.EMPLOYEE],
  },
};

/**
 * checkPermission – declarative RBAC check.
 *
 * Returns a 403 Response if the user's role is not permitted for
 * `module.action`, or null when access is granted.
 *
 * Usage (in an Edge Function):
 *   const permCheck = checkPermission(authResult.role, 'in_office', 'submit');
 *   if (permCheck) return permCheck;
 */
export function checkPermission(
  role: string,
  module: string,
  action: string,
): Response | null {
  const allowed = MODULE_PERMISSIONS[module]?.[action];
  if (!allowed) {
    // Unknown module/action — default deny to avoid silent permission gaps.
    return errorResponse(
      `Unknown permission: ${module}.${action}`,
      403,
      'FORBIDDEN',
    );
  }
  if (!allowed.includes(role)) {
    return errorResponse(
      `Access denied. Role '${role}' cannot perform '${module}.${action}'.`,
      403,
      'FORBIDDEN',
    );
  }
  return null;
}

export function requireRole(user: AuthUser, ...allowedRoles: string[]): Response | null {
  if (!allowedRoles.includes(user.role)) {
    return errorResponse(
      `Access denied. Required role: ${allowedRoles.join(' or ')}`,
      403,
      'FORBIDDEN',
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
