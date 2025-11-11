#!/usr/bin/env python3
"""
GitHub PR Metrics Analyzer
Fetches and analyzes PR metrics for specified repositories within a date range.
"""

import requests
import json
from datetime import datetime, timezone, timedelta
from typing import List, Dict, Any
import statistics
import os
import sys
import argparse
from pathlib import Path

# Load configuration from JSON file
def load_config():
    """Load configuration from github-config.json file."""
    script_dir = Path(__file__).parent
    config_path = script_dir.parent / "github-config.json"
    
    if not config_path.exists():
        print(f"Error: Configuration file not found: {config_path}", file=sys.stderr)
        print(f"Please copy github-config.json.example to github-config.json and update it with your settings.", file=sys.stderr)
        sys.exit(1)
    
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in configuration file: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error reading configuration file: {e}", file=sys.stderr)
        sys.exit(1)

def parse_arguments():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="GitHub PR Metrics Analyzer - Fetches and analyzes PR metrics for specified repositories within a date range."
    )
    
    # Calculate default dates: end = now, start = 2 weeks ago
    now = datetime.now(timezone.utc)
    default_end = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    default_start = (now - timedelta(days=14)).strftime("%Y-%m-%dT%H:%M:%SZ")
    
    parser.add_argument(
        "--start-date",
        type=str,
        default=default_start,
        help=f"Start date in ISO format (YYYY-MM-DDTHH:MM:SSZ). Default: {default_start}"
    )
    parser.add_argument(
        "--end-date",
        type=str,
        default=default_end,
        help=f"End date in ISO format (YYYY-MM-DDTHH:MM:SSZ). Default: {default_end}"
    )
    
    return parser.parse_args()

config = load_config()

# Configuration
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN") or os.getenv("GITHUB_API_TOKEN")
if not GITHUB_TOKEN:
    print("Error: Missing GitHub token. Please set the GITHUB_TOKEN environment variable.", file=sys.stderr)
    sys.exit(1)

REPOS = config.get("repos", [])

HEADERS = {
    "Authorization": f"token {GITHUB_TOKEN}",
    "Accept": "application/vnd.github.v3+json"
}

def parse_datetime(dt_str):
    """Parse GitHub datetime string to datetime object."""
    if not dt_str:
        return None
    return datetime.fromisoformat(dt_str.replace('Z', '+00:00'))

def calculate_time_diff(start_str, end_str):
    """Calculate time difference in hours between two datetime strings."""
    if not start_str or not end_str:
        return None
    start = parse_datetime(start_str)
    end = parse_datetime(end_str)
    return (end - start).total_seconds() / 3600  # Return hours

def fetch_all_pages(url, params=None):
    """Fetch all pages of a paginated GitHub API endpoint."""
    results = []
    page = 1
    while True:
        page_params = params.copy() if params else {}
        page_params['page'] = page
        page_params['per_page'] = 100
        
        response = requests.get(url, headers=HEADERS, params=page_params)
        if response.status_code != 200:
            print(f"Error fetching {url}: {response.status_code}")
            break
        
        data = response.json()
        if not data:
            break
        
        results.extend(data)
        
        # Check if there are more pages
        if 'Link' not in response.headers or 'rel="next"' not in response.headers['Link']:
            break
        
        page += 1
    
    return results

def fetch_pr_details(repo, pr_number):
    """Fetch detailed information about a specific PR."""
    url = f"https://api.github.com/repos/{repo}/pulls/{pr_number}"
    response = requests.get(url, headers=HEADERS)
    if response.status_code == 200:
        return response.json()
    return None

def fetch_pr_reviews(repo, pr_number):
    """Fetch all reviews for a PR."""
    url = f"https://api.github.com/repos/{repo}/pulls/{pr_number}/reviews"
    return fetch_all_pages(url)

def fetch_pr_comments(repo, pr_number):
    """Fetch all comments (review comments + issue comments) for a PR."""
    # Review comments (on code)
    review_comments_url = f"https://api.github.com/repos/{repo}/pulls/{pr_number}/comments"
    review_comments = fetch_all_pages(review_comments_url)
    
    # Issue comments (general PR comments)
    issue_comments_url = f"https://api.github.com/repos/{repo}/issues/{pr_number}/comments"
    issue_comments = fetch_all_pages(issue_comments_url)
    
    return review_comments + issue_comments

def analyze_pr(repo, pr):
    """Analyze a single PR and extract metrics."""
    pr_number = pr['number']
    
    # Fetch detailed PR info
    pr_details = fetch_pr_details(repo, pr_number)
    if not pr_details:
        return None
    
    # Fetch reviews
    reviews = fetch_pr_reviews(repo, pr_number)
    
    # Fetch comments
    comments = fetch_pr_comments(repo, pr_number)
    
    # Calculate time to merge (MOST IMPORTANT)
    created_at = pr_details['created_at']
    merged_at = pr_details['merged_at']
    time_to_merge_hours = calculate_time_diff(created_at, merged_at)
    
    # Calculate review time (first review to merge)
    review_time_hours = None
    first_review_time = None
    if reviews:
        review_times = [parse_datetime(r['submitted_at']) for r in reviews if r.get('submitted_at')]
        if review_times:
            first_review_time = min(review_times)
            if merged_at:
                review_time_hours = (parse_datetime(merged_at) - first_review_time).total_seconds() / 3600
    
    # Count approvals
    approvals = [r for r in reviews if r.get('state') == 'APPROVED']
    num_approvals = len(approvals)
    
    # Get unique reviewers
    reviewers = set()
    for review in reviews:
        if review.get('user') and review['user'].get('login'):
            reviewers.add(review['user']['login'])
    
    # PR size metrics
    additions = pr_details.get('additions', 0)
    deletions = pr_details.get('deletions', 0)
    changed_files = pr_details.get('changed_files', 0)
    
    return {
        'number': pr_number,
        'title': pr_details['title'],
        'url': pr_details['html_url'],
        'author': pr_details['user']['login'] if pr_details.get('user') else 'Unknown',
        'created_at': created_at,
        'merged_at': merged_at,
        'time_to_merge_hours': time_to_merge_hours,
        'time_to_merge_days': time_to_merge_hours / 24 if time_to_merge_hours else None,
        'review_time_hours': review_time_hours,
        'review_time_days': review_time_hours / 24 if review_time_hours else None,
        'num_comments': len(comments),
        'num_approvals': num_approvals,
        'num_reviewers': len(reviewers),
        'reviewers': list(reviewers),
        'additions': additions,
        'deletions': deletions,
        'changed_files': changed_files,
        'total_changes': additions + deletions
    }

def fetch_and_analyze_repo(repo, start_date, end_date):
    """Fetch and analyze all qualifying PRs for a repository."""
    print(f"\n{'='*80}")
    print(f"Analyzing repository: {repo}")
    print(f"{'='*80}")
    
    # Fetch all closed PRs
    url = f"https://api.github.com/repos/{repo}/pulls"
    params = {
        'state': 'closed',
        'sort': 'created',
        'direction': 'desc'
    }
    
    all_prs = fetch_all_pages(url, params)
    print(f"Found {len(all_prs)} closed PRs total")
    
    # Filter PRs by date range (created AND merged within range)
    start_dt = parse_datetime(start_date)
    end_dt = parse_datetime(end_date)
    
    qualifying_prs = []
    for pr in all_prs:
        created_at = parse_datetime(pr['created_at'])
        merged_at = parse_datetime(pr.get('merged_at'))
        
        # Must be merged (not just closed)
        if not merged_at:
            continue
        
        # Both created and merged must be within date range
        if start_dt <= created_at <= end_dt and start_dt <= merged_at <= end_dt:
            qualifying_prs.append(pr)
    
    print(f"Found {len(qualifying_prs)} PRs created AND merged between {start_date} and {end_date}")
    
    # Analyze each qualifying PR
    analyzed_prs = []
    for i, pr in enumerate(qualifying_prs, 1):
        print(f"Analyzing PR #{pr['number']} ({i}/{len(qualifying_prs)})...")
        metrics = analyze_pr(repo, pr)
        if metrics:
            analyzed_prs.append(metrics)
    
    return analyzed_prs

def calculate_summary_stats(prs):
    """Calculate summary statistics for a list of PRs."""
    if not prs:
        return None
    
    time_to_merge_values = [pr['time_to_merge_hours'] for pr in prs if pr['time_to_merge_hours'] is not None]
    review_time_values = [pr['review_time_hours'] for pr in prs if pr['review_time_hours'] is not None]
    comment_counts = [pr['num_comments'] for pr in prs]
    approval_counts = [pr['num_approvals'] for pr in prs]
    total_changes = [pr['total_changes'] for pr in prs]
    
    stats = {
        'total_prs': len(prs),
        'time_to_merge': {
            'mean_hours': statistics.mean(time_to_merge_values) if time_to_merge_values else 0,
            'median_hours': statistics.median(time_to_merge_values) if time_to_merge_values else 0,
            'min_hours': min(time_to_merge_values) if time_to_merge_values else 0,
            'max_hours': max(time_to_merge_values) if time_to_merge_values else 0,
        },
        'review_time': {
            'mean_hours': statistics.mean(review_time_values) if review_time_values else 0,
            'median_hours': statistics.median(review_time_values) if review_time_values else 0,
        },
        'comments': {
            'mean': statistics.mean(comment_counts) if comment_counts else 0,
            'median': statistics.median(comment_counts) if comment_counts else 0,
            'total': sum(comment_counts),
        },
        'approvals': {
            'mean': statistics.mean(approval_counts) if approval_counts else 0,
            'median': statistics.median(approval_counts) if approval_counts else 0,
        },
        'pr_size': {
            'mean_changes': statistics.mean(total_changes) if total_changes else 0,
            'median_changes': statistics.median(total_changes) if total_changes else 0,
        }
    }
    
    return stats

def format_hours(hours):
    """Format hours into a readable string."""
    if hours is None:
        return "N/A"
    
    days = int(hours // 24)
    remaining_hours = hours % 24
    
    if days > 0:
        return f"{days}d {remaining_hours:.1f}h ({hours:.1f}h total)"
    else:
        return f"{hours:.1f}h"

def generate_report(all_repo_data, start_date, end_date):
    """Generate a comprehensive markdown report."""
    report = []
    
    report.append("# GitHub PR Metrics Analysis Report")
    report.append(f"\n**Analysis Period:** {start_date} to {end_date}")
    report.append(f"\n**Date Generated:** {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
    report.append("\n---\n")
    
    for repo, prs in all_repo_data.items():
        report.append(f"\n## Repository: {repo}")
        report.append(f"\n**Total Qualifying PRs:** {len(prs)}")
        
        if not prs:
            report.append("\nNo PRs found that were both created AND merged during the specified timeframe.\n")
            continue
        
        # Summary statistics
        stats = calculate_summary_stats(prs)
        
        report.append("\n### Summary Statistics")
        report.append("\n#### ⏱️ Time to Merge (PRIMARY METRIC)")
        report.append(f"- **Mean:** {format_hours(stats['time_to_merge']['mean_hours'])}")
        report.append(f"- **Median:** {format_hours(stats['time_to_merge']['median_hours'])}")
        report.append(f"- **Min:** {format_hours(stats['time_to_merge']['min_hours'])}")
        report.append(f"- **Max:** {format_hours(stats['time_to_merge']['max_hours'])}")
        
        report.append("\n#### 👀 Review Time")
        report.append(f"- **Mean:** {format_hours(stats['review_time']['mean_hours'])}")
        report.append(f"- **Median:** {format_hours(stats['review_time']['median_hours'])}")
        
        report.append("\n#### 💬 Comments")
        report.append(f"- **Mean per PR:** {stats['comments']['mean']:.1f}")
        report.append(f"- **Median per PR:** {stats['comments']['median']:.0f}")
        report.append(f"- **Total:** {stats['comments']['total']}")
        
        report.append("\n#### ✅ Approvals")
        report.append(f"- **Mean per PR:** {stats['approvals']['mean']:.1f}")
        report.append(f"- **Median per PR:** {stats['approvals']['median']:.0f}")
        
        report.append("\n#### 📊 PR Size")
        report.append(f"- **Mean total changes:** {stats['pr_size']['mean_changes']:.0f} lines")
        report.append(f"- **Median total changes:** {stats['pr_size']['median_changes']:.0f} lines")
        
        # Individual PR details
        report.append("\n### Individual PR Details")
        report.append("\n---\n")
        
        # Sort by time to merge (descending) to highlight longest merges
        sorted_prs = sorted(prs, key=lambda x: x['time_to_merge_hours'] or 0, reverse=True)
        
        for pr in sorted_prs:
            report.append(f"\n#### PR #{pr['number']}: {pr['title']}")
            report.append(f"\n**URL:** {pr['url']}")
            report.append(f"\n**Author:** {pr['author']}")
            report.append(f"\n**Created:** {pr['created_at']}")
            report.append(f"\n**Merged:** {pr['merged_at']}")
            
            report.append(f"\n**⏱️ TIME TO MERGE:** {format_hours(pr['time_to_merge_hours'])}")
            report.append(f"\n- Review Time: {format_hours(pr['review_time_hours'])}")
            report.append(f"\n- Comments: {pr['num_comments']}")
            report.append(f"\n- Approvals: {pr['num_approvals']}")
            report.append(f"\n- Reviewers ({pr['num_reviewers']}): {', '.join(pr['reviewers']) if pr['reviewers'] else 'None'}")
            report.append(f"\n- Size: +{pr['additions']} -{pr['deletions']} lines across {pr['changed_files']} files")
            report.append("\n---\n")
    
    return "\n".join(report)

def main():
    """Main execution function."""
    args = parse_arguments()
    START_DATE = args.start_date
    END_DATE = args.end_date
    
    # Validate date format
    try:
        parse_datetime(START_DATE)
        parse_datetime(END_DATE)
    except ValueError as e:
        print(f"Error: Invalid date format. Use ISO format (YYYY-MM-DDTHH:MM:SSZ): {e}", file=sys.stderr)
        sys.exit(1)
    
    print("GitHub PR Metrics Analyzer")
    print(f"Date Range: {START_DATE} to {END_DATE}")
    print(f"Repositories: {', '.join(REPOS)}")
    
    all_repo_data = {}
    
    for repo in REPOS:
        prs = fetch_and_analyze_repo(repo, START_DATE, END_DATE)
        all_repo_data[repo] = prs
    
    # Generate report
    print("\n" + "="*80)
    print("Generating report...")
    print("="*80)
    
    report = generate_report(all_repo_data, START_DATE, END_DATE)
    
    # Save report
    output_file = "./pr_metrics_report.md"
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(report)
    
    print(f"\nReport saved to: {output_file}")
    
    # Also save as .txt
    txt_file = "./pr_metrics_report.txt"
    with open(txt_file, 'w', encoding='utf-8') as f:
        f.write(report)
    
    print(f"Report also saved to: {txt_file}")

if __name__ == "__main__":
    main()

