#!/usr/bin/env python3
"""Port the Head Manager staff screens onto the Employee screens.

Employee and Head Manager are two sides of the same job: the four modules below
must expose the exact same capabilities and the exact same layout. Rather than
hand-maintaining two drifting copies, this script regenerates the Employee
screen from its Head Manager counterpart.

What is rewritten while copying:
  * the public screen class name (HmXxxScreen -> EmpXxxScreen) so the router can
    keep importing both;
  * the leading file-path comment;
  * every relative import, re-resolved against the new file location (relative
    imports are resolved from the *source* file first, so a cross-module import
    such as ``../../ci/widgets/ci_assign_modal.dart`` keeps pointing at the very
    same file after the move);
  * the RouteConstants used for in-screen navigation (back buttons / row taps),
    mapped onto the employee route table.

Everything else — widgets, providers, layout, copy — is left byte-identical.
The data layer (RemoteDataSources) is role-agnostic, which is the same reason
``emp_active_loan_provider.dart`` already reuses ``HmLoanNotifier``.
"""

import posixpath
import re
from pathlib import Path

FEATURES = Path("lib/presentation/features")
LIB = Path("lib")

# HM route constant -> employee route constant.
ROUTE_MAP = {
    "hmAccountUpgrade": "empAccountUpgrade",
    "hmAccountUpgradeDetails": "empAccountUpgradeDetails",
    "hmLoanApplications": "empLoans",
    "hmLoanApplicationDetails": "empLoanApplicationDetails",
    "hmLoans": "empActiveLoans",
    "hmLoanDetails": "empLoanDetails",
    "hmCi": "empCi",
    "hmCiDetails": "empCiDetails",
    "hmCollections": "empCollections",
    "hmCollectionDetails": "empCollectionDetails",
    "hmDisbursements": "empDisbursements",
    "hmDisbursementDetails": "empDisbursementDetails",
    "hmPayments": "empPayments",
    "hmPaymentDetails": "empPaymentDetails",
    "hmPenalties": "empPenalties",
    "hmInOffice": "empInOffice",
    "hmLenders": "empLenders",
    "hmLenderDetails": "empLenderDetails",
    "hmRiders": "empRiders",
    "hmRiderDetails": "empRiderDetails",
}

# (source, destination, {old public class name: new public class name})
JOBS = [
    (
        "head_manager/account_upgrade/screens/hm_account_upgrade_list_screen.dart",
        "employee/account_upgrade/screens/emp_account_upgrade_list_screen.dart",
        {"HmAccountUpgradeListScreen": "EmpAccountUpgradeListScreen"},
    ),
    (
        "head_manager/account_upgrade/screens/hm_account_upgrade_details_screen.dart",
        "employee/account_upgrade/screens/emp_account_upgrade_details_screen.dart",
        {"HmAccountUpgradeDetailsScreen": "EmpAccountUpgradeDetailsScreen"},
    ),
    (
        "head_manager/loans/screens/hm_loan_applications_list_screen.dart",
        "employee/loans/screens/emp_loan_applications_screen.dart",
        {"HmLoanApplicationsListScreen": "EmpLoanApplicationsScreen"},
    ),
    (
        "head_manager/loans/screens/hm_loan_application_details_screen.dart",
        "employee/loans/screens/emp_loan_application_details_screen.dart",
        {"HmLoanApplicationDetailsScreen": "EmpLoanApplicationDetailsScreen"},
    ),
    (
        "head_manager/loans/screens/hm_loan_list_screen.dart",
        "employee/loans/screens/emp_loan_list_screen.dart",
        {"HmLoanListScreen": "EmpLoanListScreen"},
    ),
    (
        "head_manager/loans/screens/hm_loan_details_screen.dart",
        "employee/loans/screens/emp_loan_details_screen.dart",
        {"HmLoanDetailsScreen": "EmpLoanDetailsScreen"},
    ),
    (
        "head_manager/ci/screens/hm_ci_list_screen.dart",
        "employee/ci/screens/emp_ci_list_screen.dart",
        {"HmCiListScreen": "EmpCiListScreen"},
    ),
    (
        "head_manager/ci/screens/hm_ci_details_screen.dart",
        "employee/ci/screens/emp_ci_details_screen.dart",
        {"HmCiDetailsScreen": "EmpCiDetailsScreen"},
    ),
    (
        "head_manager/collections/screens/hm_collection_list_screen.dart",
        "employee/collections/screens/emp_collection_list_screen.dart",
        {"HmCollectionListScreen": "EmpCollectionListScreen"},
    ),
    (
        "head_manager/collections/screens/hm_collection_details_screen.dart",
        "employee/collections/screens/emp_collection_details_screen.dart",
        {"HmCollectionDetailsScreen": "EmpCollectionDetailsScreen"},
    ),
]

IMPORT_RE = re.compile(r"(import|export)\s+(['\"])([^'\"]+)\2;")


def rewrite_imports(text: str, src: str, dst: str) -> str:
    """Point every relative import at the same file it pointed to before."""
    src_dir = posixpath.dirname(src)
    dst_dir = posixpath.dirname(dst)

    def swap(match: "re.Match[str]") -> str:
        keyword, path = match.group(1), match.group(3)
        if not path.startswith("."):
            return match.group(0)
        resolved = posixpath.normpath(posixpath.join(src_dir, path))
        new_path = posixpath.relpath(resolved, dst_dir)
        if not new_path.startswith("."):
            new_path = "./" + new_path
        return f"{keyword} '{new_path}';"

    return IMPORT_RE.sub(swap, text)


def main() -> None:
    for src_name, dst_name, classes in JOBS:
        src_rel = posixpath.join("lib/presentation/features", src_name)
        dst_rel = posixpath.join("lib/presentation/features", dst_name)
        text = Path(src_rel).read_text(encoding="utf-8")

        for old, new in classes.items():
            text = text.replace(old, new)
        # Longest constant first so `hmCiDetails` never mutates through `hmCi`.
        for old in sorted(ROUTE_MAP, key=len, reverse=True):
            text = text.replace(f"RouteConstants.{old}", f"RouteConstants.{ROUTE_MAP[old]}")
        text = rewrite_imports(text, src_rel, dst_rel)

        # First line is the file-path banner comment.
        lines = text.split("\n")
        if lines and lines[0].startswith("// lib/"):
            lines[0] = "// " + dst_rel
        text = "\n".join(lines)

        with open(dst_rel, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        print(f"synced {dst_name}")


if __name__ == "__main__":
    main()
